{
  config,
  lib,
  pkgs,
  ...
}:

/**
  Agent-attention push — one ntfy ping whenever a coding-agent harness HALTS
  and needs the operator: a turn finished, a permission was requested, or a
  question was asked. Any act that stops execution awaiting a human.

  Single source for the cross-harness notify path: ONE script + ONE topic,
  fanned out to each harness's native hook surface — Claude Code
  `settings.json` hooks + Codex `notify=` today; OpenCode/Pi plugins next.
  Same one-input-many-generators shape as the nori.<X> effect family.

  Delivery mirrors the infra alert path (modules/infra/observability/ntfy):
  POST to ntfy.sh, where the operator's phone is already subscribed. The
  topic is a SEPARATE secret from the infra `ntfy-channel` so "an agent
  needs you" is a distinct phone subscription (and priority) from "a
  service is down".

  The topic secret is a NixOS sops secret rendered to `topicFile`; this home
  module only READS it at runtime, so it stays disabled on hosts that don't
  provision it (macbook).
*/

let
  cfg = config.nori.agentNotify;

  agent-notify = pkgs.writeShellApplication {
    name = "agent-notify";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      # agent-notify <harness> <event> [json]
      #   harness : claude | codex | opencode | pi
      #   event   : stop | permission | question | notification
      #   json    : optional payload. Codex passes it as the trailing arg;
      #             Claude Code pipes it on stdin. Best-effort — a missing or
      #             unparseable payload never blocks the ping.
      harness="''${1:-agent}"
      event="''${2:-stop}"
      payload="''${3:-}"
      if [ -z "$payload" ] && [ ! -t 0 ]; then
        payload="$(cat)"
      fi

      topic_file=${lib.escapeShellArg cfg.topicFile}
      if [ ! -r "$topic_file" ]; then
        echo "agent-notify: topic secret $topic_file unreadable; skipping ping" >&2
        exit 0
      fi
      topic="$(< "$topic_file")"

      # cwd: prefer the payload's project dir, fall back to the notify process's
      # own cwd (Codex spawns notify with the session's working dir).
      cwd="$(printf '%s' "$payload" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)"
      [ -n "$cwd" ] || cwd="$PWD"
      dir="$(basename "$cwd")"

      # Identity line: who + where. Herdr pane title tells the operator WHICH
      # agent halted when several run at once.
      where="${config.home.username}@$(uname -n)"
      pane="''${HERDR_PANE_TITLE:-''${HERDR_PANE:-}}"
      if [ -n "$pane" ]; then
        where="$where · $pane"
      fi

      case "$event" in
        permission)   prio="high";    tags="warning,lock";     verb="needs permission" ;;
        question)     prio="high";    tags="grey_question";    verb="is asking" ;;
        notification) prio="high";    tags="bell";             verb="needs you" ;;
        *)            prio="default"; tags="white_check_mark"; verb="finished a turn" ;;
      esac

      curl -fsS \
        -H "Title: $harness $verb — $dir" \
        -H "Priority: $prio" \
        -H "Tags: $tags" \
        --data-binary "$(printf '%s\n%s' "$where" "$cwd")" \
        "${cfg.baseUrl}/$topic" >/dev/null || true
    '';
  };
in
{
  options.nori.agentNotify = {
    enable = lib.mkEnableOption "phone push when a coding-agent harness halts (turn end / permission / question)";

    topicFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/ntfy-agents-channel";
      description = ''
        Path to the rendered ntfy topic secret. A NixOS sops secret
        provisions it (owner nori); this home module only reads it at
        runtime. Left as a default so tests can point it at a stub.
      '';
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = ''
        ntfy base URL; topic appended as a path segment. Matches the infra
        alert path (ntfy.sh, where the phone is already subscribed).
      '';
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${agent-notify}/bin/agent-notify";
      description = ''
        Absolute path to the notify entrypoint, for harness modules to wire
        into their native hook surface (Claude hooks, Codex notify, …).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ agent-notify ];
  };
}
