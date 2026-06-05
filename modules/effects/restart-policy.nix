{ lib, ... }:

# Default restart policy for every systemd service on every host.
#
# ── Why this exists ─────────────────────────────────────────────────
# Stock systemd lets a broken service tight-loop: ExecStart fails,
# RestartSec elapses (default 100ms!), restart, fail, repeat — burning
# CPU and spamming the journal. Worse, it never gives up, and nothing
# tells the operator the unit is wedged.
#
# This module imposes three system-wide invariants:
#
# 1. **Exponential backoff.** Starts at 1s and ramps to a 5-min ceiling
#    over 9 steps. Sequence: 1s, ~2s, ~4s, ~8s, ~15s, ~30s, ~1min,
#    ~2min, ~5min, ~5min … . A transient bind/dependency hiccup
#    self-heals in seconds; a real fault stops eating CPU within
#    minutes. Requires systemd ≥254 (NixOS 25.05+).
#
# 2. **Give up eventually.** `StartLimitIntervalSec=1h` +
#    `StartLimitBurst=15` means after 15 restarts in an hour systemd
#    enters a rate-limit state and stops trying. Combined with the
#    backoff above, that's "ramp through the ladder and then sit at
#    5min for a few attempts; if it's still failing, you're done."
#
# 3. **Alert the operator.** OnFailure → notify@%n.service for every
#    service that doesn't already declare its own OnFailure. The
#    template lives in modules/server/ntfy/notify.nix and posts to
#    ntfy.sh with the unit name + hostname so the mobile app surfaces
#    it. Per-service explicit OnFailure (e.g. backup jobs that want a
#    richer alert) still wins via mkDefault.
#
# ── How it's wired ──────────────────────────────────────────────────
# We extend the *type* of `systemd.services` so the merged submodule
# applies the defaults inside every service instance. The naïve
# `config.systemd.services = mapAttrs … config.systemd.services` trick
# infinite-recurses (read-back of the value we're writing); this
# type-level shape is the canonical NixOS pattern for "settings that
# apply to every X in an attrsOf submodule option."
#
# ── Per-service override ────────────────────────────────────────────
# Everything here is mkDefault, so a service that genuinely needs
# different semantics (a oneshot that intentionally exits non-zero, a
# socket-activated unit that shouldn't restart, etc.) just declares
# its own `serviceConfig.Restart`, `unitConfig.OnFailure = lib.mkForce
# [ ]`, etc., and the explicit setting wins.
#
# ── Exclusions ──────────────────────────────────────────────────────
# The `notify@` template itself is excluded — if it failed, sending a
# notify@notify@%i.service alert would just fail again, forever.

{
  options.systemd.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        let
          # A service is "trying to stay up" when it has any Restart=
          # value other than "no" (or has none, which systemd treats as
          # "no" by default). Backoff settings are inert for non-restart
          # services so they apply universally without harm. OnFailure
          # only applies when restart is enabled — for oneshots and
          # one-time activation jobs, exit≠0 isn't necessarily a fault,
          # and a blanket ntfy would be noisy.
          restartEnabled = (config.serviceConfig.Restart or "no") != "no";
        in
        {
          config = lib.mkIf (name != "notify@") {
            serviceConfig = {
              RestartSec = lib.mkDefault "1s";
              RestartSteps = lib.mkDefault 9;
              RestartMaxDelaySec = lib.mkDefault "5min";
              StartLimitIntervalSec = lib.mkDefault "1h";
              StartLimitBurst = lib.mkDefault 15;
            };
            unitConfig.OnFailure = lib.mkIf restartEnabled (
              # `${name}.service`, not the `%n` specifier — `%n` expands
              # to the full unit name *with* `.service`, so
              # `notify@%n.service` would render as
              # `notify@caddy.service.service` (template + instance +
              # suffix). The literal interpolation gives
              # `notify@caddy.service`, matching the existing manual
              # uses in backup.nix and btrbk.nix.
              lib.mkDefault [ "notify@${name}.service" ]
            );
          };
        }
      )
    );
  };
}
