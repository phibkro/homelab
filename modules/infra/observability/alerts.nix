{
  config,
  lib,
  pkgs,
  ...
}:

/**
  nori.alerts — the single alert emit-point + routing table.

  Models the flow the producers used to hand-roll:

      EVENT      something happened (unit failed, disk low, agent halted)
        │        recorded as a fact in journald → VictoriaLogs
        ▼
      ALERT      a decision it's worth attention: severity · category · AUDIENCE
        │        emitted via `nori-alert`; logged, then routed
        ▼
      CHANNELS   routes.<audience> → one alert fans out to N channels
                 (ntfy topics today; email/other kinds later)

  Before this, "how to send an alert" (ntfy URL + channel secret + curl +
  tag vocabulary) was copy-pasted across notify@, disk-alert, and
  agent-notify — the convention rung, three copies free to drift. Here it's
  one construct; a producer declares INTENT (`--audience operator`), routing
  owns delivery. Adding a channel or re-routing is one config edit, no
  producer touched. Same collected-Writer shape as nori.lanRoutes.

  A producer never names a channel — it names an audience. The audience→
  channel map lives with whoever provisions the channel secret (infra
  channel + operator route in ntfy/notify.nix; agents channel + agents
  route on the workstation that runs the fleet).

  Scope: v1 is the seam + routing + a structured log line, NOT a durable
  transactional outbox. Delivery is still best-effort fire-and-forget (as
  it was). A spool/retry relay that survives ntfy.sh being unreachable is a
  later rung — add it if we measure dropped alerts, not before.
*/

let
  cfg = config.nori.alerts;

  channelType = lib.types.submodule {
    options = {
      kind = lib.mkOption {
        type = lib.types.enum [ "ntfy" ];
        default = "ntfy";
        description = "Channel delivery kind. Only ntfy today; the enum is the seam for email/other later.";
      };
      topicSecret = lib.mkOption {
        type = lib.types.str;
        description = "Path to the rendered ntfy topic secret (sops). Read at send time by the caller's uid.";
      };
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ntfy.sh";
        description = "ntfy base URL; topic appended as a path segment.";
      };
    };
  };

  # One post_<channel> shell function per channel — reads its secret and
  # curls. Kept per-channel (not a data loop) because each closes over a
  # distinct secret path resolved at build.
  postFn = name: ch: ''
    post_${name}() {
      if [ ! -r ${lib.escapeShellArg ch.topicSecret} ]; then
        echo "nori-alert: channel ${name} secret unreadable; skipping" >&2
        return 0
      fi
      local topic
      topic="$(cat ${lib.escapeShellArg ch.topicSecret})"
      curl -fsS \
        -H "Title: $title" \
        -H "Priority: $prio" \
        -H "Tags: $tags" \
        --data-binary "$body" \
        "${ch.baseUrl}/$topic" >/dev/null || true
    }
  '';

  routeArm = audience: channels: ''
    ${audience}) ${lib.concatMapStringsSep " " (c: "post_${c}") channels} ;;
  '';

  nori-alert = pkgs.writeShellApplication {
    name = "nori-alert";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      # nori-alert --audience <a> --severity <info|warning|urgent> \
      #            [--category <c>] --title <t> [--body <b>] [--tags <a,b>]
      # Body may also arrive on stdin. A producer names an AUDIENCE, never a
      # channel; routing (nori.alerts.routes) fans out to channels.
      audience="" severity="info" category="" title="" body="" extra_tags=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --audience) audience="$2"; shift 2 ;;
          --severity) severity="$2"; shift 2 ;;
          --category) category="$2"; shift 2 ;;
          --title)    title="$2";    shift 2 ;;
          --body)     body="$2";     shift 2 ;;
          --tags)     extra_tags="$2"; shift 2 ;;
          *) echo "nori-alert: unknown argument: $1" >&2; exit 2 ;;
        esac
      done
      if [ -z "$body" ] && [ ! -t 0 ]; then
        body="$(cat)"
      fi
      : "''${title:?nori-alert: --title required}"
      : "''${audience:?nori-alert: --audience required}"

      # severity → ntfy priority + a default tag
      case "$severity" in
        urgent)  prio="urgent";  stag="rotating_light" ;;
        warning) prio="high";    stag="warning" ;;
        *)       prio="default"; stag="information_source" ;;
      esac
      tags="$stag"
      if [ -n "$category" ];   then tags="$tags,$category"; fi
      if [ -n "$extra_tags" ]; then tags="$tags,$extra_tags"; fi

      # Structured log line → journald → VictoriaLogs: the alert IS an event,
      # recorded as a fact before (and regardless of) delivery success.
      echo "nori-alert audience=$audience severity=$severity category=''${category:-none} title=\"$title\"" >&2

      ${lib.concatStrings (lib.mapAttrsToList postFn cfg.channels)}

      case "$audience" in
        ${lib.concatStrings (lib.mapAttrsToList routeArm cfg.routes)}
        *) echo "nori-alert: no route for audience=$audience (see nori.alerts.routes)" >&2; exit 1 ;;
      esac
    '';
  };
in
{
  options.nori.alerts = {
    channels = lib.mkOption {
      type = lib.types.attrsOf channelType;
      default = { };
      description = "Delivery endpoints. Defined alongside whoever provisions the topic secret.";
    };

    routes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        operator = [ "infra" ];
        agents = [ "agents" ];
      };
      description = "audience → channel names. One alert fans out to every listed channel.";
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${nori-alert}/bin/nori-alert";
      description = "Absolute path to the emit-point, for producers to call (also on the system PATH).";
    };
  };

  # Install whenever any channel is declared — nori-alert is the emit-point
  # every producer resolves via PATH or nori.alerts.command.
  config = lib.mkIf (cfg.channels != { }) {
    environment.systemPackages = [ nori-alert ];
  };
}
