{
  config,
  lib,
  pkgs,
  ...
}:

/**
  herdr-monitor — the fleet's attention daemon.

  A Bun daemon that polls Herdr session sockets, matches agent lane states
  against escalation policies, and reacts: wakes the manager pane, pings the
  operator via the desktop command (ntfy bridge), or fires an idle
  notification. Previously a HAND-INSTALLED user unit + a hand-edited
  config.json (with a farm of .bak files) — this module makes both
  declarative so the desired state has a single source and drift is
  unrepresentable.

  This is the capability's realization for the agentic workstation: gated
  behind `nori.herdrMonitor.enable`, selected in the agentic-tools profile,
  and switched on by the workstation profile alongside nori.agentNotify.

  FUTURE WORK: the monitor's TypeScript still lives in the repo checkout at
  /srv/share/projects/herdr-monitor/monitor.ts — the source of truth is that
  working tree, not the Nix store. Packaging monitor.ts (+ its ntfy-notify
  bridge and escalation-policy.md) into the store and pointing ExecStart at
  the immutable path is a follow-up; keeping the checkout path here matches
  how the daemon is developed and iterated today.
*/

let
  cfg = config.nori.herdrMonitor;

  monitorSource = "/srv/share/projects/herdr-monitor/monitor.ts";

  configFormat = pkgs.formats.json { };

  # Ported verbatim from the live hand-edited
  # ~/.config/herdr-monitor/config.json (2026-07-24) — this attrset is now
  # the single source of that desired state. Override via `settings`.
  defaultSettings = {
    version = 1;
    session = "projects";
    pollIntervalMs = 5000;
    herdrCommand = "/etc/profiles/per-user/nori/bin/herdr";
    desktopCommand = "/srv/share/projects/herdr-monitor/bin/ntfy-notify";
    stateFile = "/home/nori/.local/state/herdr-monitor/state.json";
    eventLog = "/home/nori/.local/state/herdr-monitor/events.jsonl";
    sessionSockets = {
      default = "/home/nori/.config/herdr/herdr.sock";
      index = "/home/nori/.config/herdr/sessions/index/herdr.sock";
      projects = "/home/nori/.config/herdr/sessions/projects/herdr.sock";
      manager = "/home/nori/.config/herdr/sessions/manager/herdr.sock";
    };
    notifications = {
      herdr = false;
      desktop = true;
    };
    managerWake = {
      enabled = true;
      session = "manager";
      paneId = "w1:p1";
      harness = "claude";
    };
    managerIdleNotification = {
      enabled = true;
      session = "manager";
      paneId = "w1:p1";
      idleForMs = 60000;
      command = "/etc/profiles/per-user/nori/bin/agent-notify";
      harness = "claude";
    };
    policies = [
      {
        id = "context-rot";
        label = "Lane context near exhaustion — handoff now";
        mode = "any";
        select.labels = [
          "engineering*"
          "engineer"
          "*-engineer"
          "product-*"
          "advisor"
          "advisor-*"
          "*-advisor"
          "lead"
          "lead-*"
          "*-lead"
          "operations"
        ];
        when = [
          "working"
          "idle"
          "done"
          "blocked"
        ];
        contextLeftPercentAtMost = 20;
        codexContextWindowTokens = 258000;
        wakeManager = true;
        notifyInitial = true;
        sound = "request";
      }
      {
        id = "engineering-blocked";
        label = "Engineer needs attention";
        mode = "any";
        select.labels = [
          "engineering*"
          "engineer"
          "*-engineer"
        ];
        when = [ "blocked" ];
        wakeManager = true;
        notifyInitial = true;
        sound = "request";
        wakeGraceMs = 12000;
      }
      {
        id = "management-blocked";
        label = "Lead or advisor needs attention";
        mode = "any";
        select.labels = [
          "product-*"
          "advisor"
          "advisor-*"
          "*-advisor"
          "lead"
          "lead-*"
          "*-lead"
          "operations"
        ];
        when = [ "blocked" ];
        wakeManager = true;
        notifyInitial = true;
        sound = "request";
      }
      {
        id = "management-complete";
        label = "Lead or advisor completed";
        mode = "any";
        select.labels = [
          "product-*"
          "advisor"
          "advisor-*"
          "*-advisor"
          "lead"
          "lead-*"
          "*-lead"
          "operations"
        ];
        when = [ "done" ];
        notifyInitial = false;
        sound = "done";
      }
      {
        id = "lane-settled";
        label = "Lane finished — done or idle";
        mode = "any";
        select.labels = [
          "engineering*"
          "engineer"
          "*-engineer"
          "product-*"
          "advisor"
          "advisor-*"
          "*-advisor"
          "lead"
          "lead-*"
          "*-lead"
          "operations"
        ];
        when = [
          "done"
          "idle"
        ];
        notifyInitial = true;
        sound = "done";
      }
      {
        id = "all-engineering-settled";
        label = "Project idle — whole team settled";
        mode = "all";
        groupBy = "workspace";
        select.labels = [
          "engineering*"
          "engineer"
          "*-engineer"
          "product-*"
          "advisor"
          "advisor-*"
          "*-advisor"
          "lead"
          "lead-*"
          "*-lead"
          "operations"
        ];
        when = [
          "idle"
          "done"
        ];
        wakeManager = true;
        minimumTargets = 1;
        notifyInitial = true;
        sound = "done";
        cooldownMs = 1800000;
      }
    ];
  };
in
{
  options.nori.herdrMonitor = {
    enable = lib.mkEnableOption "policy-driven Herdr agent monitor (fleet attention daemon)";

    settings = lib.mkOption {
      type = configFormat.type;
      default = defaultSettings;
      description = ''
        The monitor's config.json, rendered to
        ~/.config/herdr-monitor/config.json. Defaults to the live desired
        state (session sockets, manager wake/idle pane, escalation
        policies); override to tune without hand-editing the deployed file.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."herdr-monitor/config.json".source =
      configFormat.generate "herdr-monitor-config.json" cfg.settings;

    # Equivalent to the retired hand-installed user unit, with bun resolved
    # from the store instead of ~/.nix-profile. herdrCommand / agent-notify /
    # desktopCommand are absolute in the config, so PATH only needs the
    # per-user profile parity the daemon expects.
    systemd.user.services.herdr-monitor = {
      Unit = {
        Description = "Policy-driven Herdr agent monitor";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "HOME=${config.home.homeDirectory}"
          "PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin"
        ];
        ExecStart = "${pkgs.bun}/bin/bun ${monitorSource} --config ${config.xdg.configHome}/herdr-monitor/config.json";
        Restart = "always";
        RestartSec = 3;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
