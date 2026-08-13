{
  config,
  lib,
  pkgs,
  ...
}:

/**
  Per-user systemd restart policy — the home-manager twin of
  modules/infra/restart-policy.nix.

  That module hardens `systemd.services` (the system manager). Nothing
  covered `systemd.user.services`, so every user unit kept stock systemd's
  behaviour: tight-restart forever, tell nobody. herdr-monitor.service
  crash-looped 22500+ times over roughly a day on workstation before anyone
  noticed — the fleet's wake mechanism was dead the whole time and the only
  evidence was in `journalctl --user`. The homelab rule "don't bypass the
  safety net — OnFailure → ntfy alerts" had simply never crossed from system
  units to user units.

  Same three invariants as the system module:

  1. Exponential backoff (RestartSec 1s → ~5min over 9 steps).
  2. Give up eventually (StartLimitIntervalSec=1h + StartLimitBurst=15), so a
     broken unit lands in `failed` instead of looping until the next reboot.
  3. Alert on failure (OnFailure → user-notify@%n) for any unit trying to stay
     up.

  Wired by extending the *type* of `systemd.user.services` so the defaults
  apply inside every unit. home-manager's unit type is a `types.submodule`
  with a freeform body, so the same type-level shape the system module uses
  works here; the naive `mapAttrs` over the option value infinite-recurses.

  Note the shape difference from the system module: home-manager units use
  the literal systemd section names (`Unit` / `Service` / `Install`), not
  NixOS's `unitConfig` / `serviceConfig`.

  SCOPE LIMIT, stated because it is the interesting half: this covers units
  home-manager declares. A unit hand-dropped into ~/.config/systemd/user/
  gets none of it — and that is exactly what herdr-monitor.service was. The
  structural fix for that class is to bring such units under home-manager;
  this module makes the declarative path safe, it cannot reach outside it.
*/

let
  cfg = config.nori.userRestartPolicy;

  /*
    nori-alert is a *system* binary. Resolving it at runtime rather than
    through osConfig keeps this module working on standalone home-manager
    (macbook, no NixOS), matching how modules/home/agent-notify does it.
    Absent → exit quietly; an alerting path must never itself become the
    thing that fails.
  */
  user-notify = pkgs.writeShellApplication {
    name = "user-notify";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      UNIT="''${1:?unit name required}"

      # Wait out the restart ladder before alerting: most transient failures
      # self-heal inside it, and an alert that fires during recovery is stale
      # by the time the phone lights up. Mirrors the system notify@ template.
      sleep ${toString cfg.recoveryWindowSeconds}

      # Alert only when systemd still classifies the unit as failed. Merely
      # being inactive is not a fault: graphical-session teardown, an
      # operator stop, a condition skip, and a completed oneshot all land
      # there. An auto-restarting unit is "activating", so this also avoids
      # one phone alert per failed attempt while the restart ladder is live.
      if ! systemctl --user is-failed "$UNIT" --quiet; then
        exit 0
      fi

      nori_alert="$(command -v nori-alert || true)"
      if [ -z "$nori_alert" ] && [ -x /run/current-system/sw/bin/nori-alert ]; then
        nori_alert=/run/current-system/sw/bin/nori-alert
      fi
      if [ -z "$nori_alert" ]; then
        echo "user-notify: nori-alert not found; skipping alert for $UNIT" >&2
        exit 0
      fi

      # Last 8 lines / 800 chars fits ntfy's body limit without truncation.
      TAIL="$(journalctl --user -u "$UNIT" -n 8 --no-pager 2>&1 | tail -c 800)"

      "$nori_alert" \
        --audience operator \
        --severity urgent \
        --category service-failure \
        --title "$(uname -n): user unit $UNIT persistently failed" \
        --body "$UNIT remains in systemd's failed state in ${config.home.username}'s user manager after the recovery window. Recent journal:

      $TAIL

      Diagnose: journalctl --user -u $UNIT" || true
    '';
  };
in
{
  options.nori.userRestartPolicy = {
    /*
      Linux-only by construction: `systemd.user.services` is a no-op on
      darwin, and pkgs.systemd does not build there — so the macbook's
      standalone home evaluates this module to nothing rather than failing on
      an unbuildable runtime input.
    */
    enable = lib.mkEnableOption "backoff + give-up + ntfy alerting for user units" // {
      default = pkgs.stdenv.hostPlatform.isLinux;
    };

    recoveryWindowSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        Seconds to wait after OnFailure fires before alerting, so a unit that
        recovers during the restart backoff stays quiet.

        Deliberately a separate knob from the system-side
        `nori.observability.ntfyNotify.recoveryWindowSeconds` rather than a
        reference to it: home-manager and NixOS are separate module trees and
        this module avoids `osConfig` so standalone (macbook) evaluation keeps
        working. The number is therefore hand-synced — the weakest rung of the
        derivation ladder. It is tolerable only because the value is inert
        policy, not a correctness invariant; if these ever need to agree by
        construction, the fix is to thread `osConfig` for NixOS hosts and make
        the standalone case explicit.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    /*
      The alert handler itself is excluded from the policy below — pointing
      user-notify@'s OnFailure at user-notify@ would recurse forever.
    */
    systemd.user.services."user-notify@" = {
      Unit.Description = "Alert operator that user unit %i is still failed";
      Service = {
        Type = "oneshot";
        ExecStart = "${user-notify}/bin/user-notify %i";
        # The sleep must run uninterrupted; slack over the window covers
        # journalctl + curl.
        TimeoutStartSec = "${toString (cfg.recoveryWindowSeconds + 60)}s";
      };
    };
  };

  options.systemd.user.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        let
          /*
            A unit is "trying to stay up" iff Restart= is anything but "no".
            OnFailure only fires when restart is enabled — for oneshots a
            nonzero exit isn't necessarily a fault, and blanket alerting would
            be noisy. The backoff keys are inert for non-restart units, so they
            apply universally without harm.
          */
          restartEnabled = (config.Service.Restart or "no") != "no";
        in
        {
          config = lib.mkIf (cfg.enable && name != "user-notify@") {
            Service = {
              RestartSec = lib.mkDefault "1s";
              RestartSteps = lib.mkDefault 9;
              RestartMaxDelaySec = lib.mkDefault "5min";
            };
            /*
              StartLimit* are [Unit] directives, not [Service]. Putting them
              under Service makes systemd ignore them with "Unknown key ... in
              section [Service]" and the give-up cap silently never applies —
              the exact bug caught on restic-backups-*-mp510, 2026-06-06.
            */
            Unit.StartLimitIntervalSec = lib.mkDefault "1h";
            Unit.StartLimitBurst = lib.mkDefault 15;
            /*
              Literal `${name}.service` rather than systemd's %n, which already
              carries the .service suffix and would render user-notify@waybar
              .service.service.
            */
            Unit.OnFailure = lib.mkIf restartEnabled (lib.mkDefault [ "user-notify@${name}.service" ]);
          };
        }
      )
    );
  };
}
