{ config, lib, ... }:

# System-wide systemd restart policy.
#
# Stock systemd tight-loops a broken unit at RestartSec=100ms forever
# and never tells anyone. This module imposes three invariants:
#
# 1. Exponential backoff. 1s → ~2 → ~4 → ~8 → ~15 → ~30 → ~1min →
#    ~2min → ~5min, then sits at the 5-min ceiling. Transient hiccups
#    self-heal in seconds; real faults stop burning CPU within minutes.
#    Requires systemd ≥254 (NixOS 25.05+).
# 2. Give up eventually. StartLimitIntervalSec=1h + StartLimitBurst=15:
#    ramp the ladder, sit at 5min for a few attempts, then stop.
# 3. Alert on failure. OnFailure → notify@%n.service for any service
#    that doesn't declare its own (template: modules/services/ntfy/).
#
# Wired by extending the *type* of `systemd.services` so the defaults
# apply inside every submodule instance. The naïve
# `config.systemd.services = mapAttrs … config.systemd.services` form
# infinite-recurses (read-back of the value being written) — this
# type-level shape is the canonical NixOS pattern for "apply to every
# X in an attrsOf submodule."

let
  # notify@ template lives in modules/services/ntfy/notify.nix. Hosts
  # that don't import it (pavilion — agent-quarantine, no notify
  # infrastructure) shouldn't get OnFailure pointed at a missing unit.
  hasNotifyTemplate = config.systemd.services ? "notify@";
in
{
  options.systemd.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        let
          # A unit is "trying to stay up" iff Restart= is anything but
          # "no". OnFailure only fires when restart is enabled — for
          # oneshots, exit≠0 isn't necessarily a fault and blanket ntfy
          # would be noisy. Backoff settings are inert for non-restart
          # units so they apply universally without harm.
          restartEnabled = (config.serviceConfig.Restart or "no") != "no";
        in
        {
          # notify@ is excluded — if it failed, sending
          # notify@notify@%i.service would just fail again, forever.
          config = lib.mkIf (name != "notify@") {
            serviceConfig = {
              RestartSec = lib.mkDefault "1s";
              RestartSteps = lib.mkDefault 9;
              RestartMaxDelaySec = lib.mkDefault "5min";
            };
            # StartLimitIntervalSec + StartLimitBurst are [Unit] section
            # directives, NOT [Service]. Putting them in serviceConfig
            # makes systemd silently ignore them with
            #   Unknown key 'StartLimitIntervalSec' in section [Service]
            # — so the "give up after 15 restarts/h" cap never applied.
            # Caught on restic-backups-*-mp510 failure 2026-06-06
            # (target was named `ironwolf` then; renamed in P14
            # when the data moved off the IronWolf to the MP510).
            unitConfig.StartLimitIntervalSec = lib.mkDefault "1h";
            unitConfig.StartLimitBurst = lib.mkDefault 15;
            # Literal `${name}.service` instead of systemd's %n — %n
            # already includes .service, so notify@%n.service renders
            # as notify@caddy.service.service.
            unitConfig.OnFailure = lib.mkIf (restartEnabled && hasNotifyTemplate) (
              lib.mkDefault [ "notify@${name}.service" ]
            );
          };
        }
      )
    );
  };
}
