{
  config,
  lib,
  pkgs,
  ...
}:

/**
  agent-notify — maps a coding-agent harness event to a nori.alerts emit.

  A harness HALTS and needs the operator (turn finished / permission asked /
  question asked). This script knows the harness semantics — which event,
  the project dir, the herdr pane — and translates that into ONE
  `nori-alert --audience agents …` call. Delivery (topic, priority, curl)
  is nori.alerts' job, not this script's; this is just the event→alert
  mapper, so there's a single delivery construct across every producer.

  Wiring (unchanged interface): every harness calls `agent-notify <harness>
  <event>` from its native hook surface — Claude Code Stop/Notification
  hooks, the Codex notify wrapper, an OpenCode plugin, and a Pi extension
  (the last two are the .ts files beside this module, dropped via home.file
  below). The `agents` audience routes to the agents ntfy topic — defined by
  the host that runs the fleet (modules/machines/workstation/default.nix),
  since that's where the topic secret and nori-alert live. On a host without
  nori.alerts the enable stays off.
*/

let
  cfg = config.nori.agentNotify;

  agent-notify = pkgs.writeShellApplication {
    name = "agent-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      # agent-notify <harness> <event> [json]
      #   harness : claude | codex | opencode | pi
      #   event   : stop | permission | question | notification
      #   json    : optional payload. Codex passes it as the trailing arg;
      #             Claude Code pipes it on stdin. Best-effort.
      harness="''${1:-agent}"
      event="''${2:-stop}"

      # Herdr owns in-app attention, not the nori-alert phone route. Preserve
      # stop pushes for background project agents while leaving its native
      # needs-input handling authoritative for permission and question events.
      if [ "''${HERDR_ENV:-}" = 1 ] && [ "$event" != stop ]; then
        exit 0
      fi
      payload="''${3:-}"
      if [ -z "$payload" ] && [ ! -t 0 ]; then
        payload="$(cat)"
      fi

      # nori-alert is a system binary; resolve it explicitly so a stripped
      # hook PATH still finds it. Absent (non-NixOS) → skip, never block.
      nori_alert="$(command -v nori-alert || true)"
      if [ -z "$nori_alert" ] && [ -x /run/current-system/sw/bin/nori-alert ]; then
        nori_alert=/run/current-system/sw/bin/nori-alert
      fi
      if [ -z "$nori_alert" ]; then
        echo "agent-notify: nori-alert not found; skipping ping" >&2
        exit 0
      fi

      # cwd: prefer the payload's project dir, else the notify process's cwd.
      cwd="$(printf '%s' "$payload" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)"
      [ -n "$cwd" ] || cwd="$PWD"
      dir="$(basename "$cwd")"

      # Identity line: who + where. Herdr pane title says WHICH agent halted.
      where="${config.home.username}@$(uname -n)"
      pane="''${HERDR_PANE_TITLE:-''${HERDR_PANE:-}}"
      if [ -n "$pane" ]; then
        where="$where · $pane"
      fi

      case "$event" in
        permission)   severity="warning"; category="agent-permission"; verb="needs permission" ;;
        question)     severity="warning"; category="agent-question";   verb="is asking" ;;
        notification) severity="warning"; category="agent-attention";  verb="needs you" ;;
        *)            severity="info";    category="agent-stop";        verb="finished a turn" ;;
      esac

      "$nori_alert" \
        --audience agents \
        --severity "$severity" \
        --category "$category" \
        --title "$harness $verb — $dir" \
        --body "$(printf '%s\n%s' "$where" "$cwd")" || true
    '';
  };
in
{
  options.nori.agentNotify = {
    enable = lib.mkEnableOption "phone push when a coding-agent harness halts (turn end / permission / question)";

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${agent-notify}/bin/agent-notify";
      description = ''
        Absolute path to the mapper, for harness modules to wire into their
        native hook surface (Claude hooks, Codex notify, …).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ agent-notify ];

    # OpenCode + Pi legs — pure file drops. Neither self-mutates its config
    # (config and mutable state live on separate roots), so read-only store
    # symlinks are safe. Inert when the harness isn't installed; each just
    # calls `agent-notify` (on PATH) on a halt event.
    #   OpenCode: one `event` hook, switched on session.idle / permission.v2
    #             .asked / question.v2.asked.
    #   Pi:       `agent_settled` (its "won't continue on its own" signal;
    #             no built-in permission/question prompt — stop-only, like Codex).
    home.file.".config/opencode/plugin/agent-notify.ts".source = ./opencode-plugin.ts;
    home.file.".pi/agent/extensions/agent-notify.ts".source = ./pi-extension.ts;
  };
}
