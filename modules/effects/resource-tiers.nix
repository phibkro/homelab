{
  config,
  lib,
  ...
}:

# Resource tiers — declarative cgroup limits + an OOM safety valve.
#
# ── Why this exists ───────────────────────────────────────────────
# Workstation now runs a mix of heavy services (immich-machine-
# learning, ollama with multi-GB models warm, open-webui, hermes-
# dashboard, the *arr stack, …) on a single host. Without limits, a
# single mis-behaving service can balloon and trigger the kernel
# OOM-killer, which picks targets purely by oom_score_adj —
# frequently knocking out something critical like Caddy or sshd
# while leaving the offender alive.
#
# This module imposes one declaration per service:
#
#   nori.resourceTier.<unit> = "critical" | "important" | "heavy" | "decorative";
#
# Each tier maps to a cgroup limit profile (CPUWeight, MemoryHigh,
# MemoryMax, IOWeight, OOMScoreAdjust). A service that doesn't
# declare a tier defaults to "important" — the middle posture —
# but a guard derivation can later require explicit declaration
# the same way nori.backups already does.
#
# ── Tiers ─────────────────────────────────────────────────────────
#
#   critical    — keep this up at all costs. Caddy, blocky, authelia,
#                 sshd, tailscaled, the notify@ template. No memory
#                 cap (limited only by host RAM); top CPU weight;
#                 OOMScoreAdjust=-500 so they're last killed.
#
#   important   — needs to stay up under normal load but is reclaimable
#                 under genuine pressure. Beszel, gatus, immich-server,
#                 jellyfin, vaultwarden. Modest MemoryHigh (reclaim
#                 trigger), MemoryMax double that (hard ceiling).
#
#   heavy       — known-large RAM users. Large MemoryHigh, can be paged
#                 / swapped under pressure. ollama, immich-machine-
#                 learning, open-webui. Higher OOMScoreAdjust so the
#                 OOM safety valve targets these first when something
#                 has to die.
#
#   decorative  — nice-to-have, first reclaimed. hermes-dashboard
#                 (the web UI; the agent itself isn't always-on),
#                 dashboard-style services. Tight MemoryHigh, low
#                 CPUWeight, OOMScoreAdjust=500.
#
# ── Safety valve ──────────────────────────────────────────────────
# `systemd-oomd` is enabled below. When global memory pressure
# crosses the configured PSI threshold the daemon kills the cgroup
# with the highest pressure contribution (NOT the kernel's
# oom_score_adj heuristic). This means decorative + heavy tiers are
# usually killed first under genuine pressure, while critical units
# are protected both by their own absence of limits and by
# oomd's pressure-based targeting.

let
  inherit (lib) mkOption types;

  # Tier → systemd serviceConfig profile. These numbers are starting
  # points calibrated for a ~64 GB workstation; tune per host if the
  # host's RAM differs by an order of magnitude.
  profiles = {
    critical = {
      CPUWeight = 1000;
      IOWeight = 1000;
      # No MemoryHigh — critical services get the whole host's
      # memory if they really need it. The point is to keep them
      # ALIVE, not to shape them.
      OOMScoreAdjust = -500;
    };
    important = {
      CPUWeight = 200;
      IOWeight = 200;
      MemoryHigh = "2G";
      MemoryMax = "4G";
      OOMScoreAdjust = 0;
    };
    heavy = {
      CPUWeight = 100;
      IOWeight = 100;
      MemoryHigh = "8G";
      MemoryMax = "16G";
      OOMScoreAdjust = 200;
    };
    decorative = {
      CPUWeight = 50;
      IOWeight = 50;
      MemoryHigh = "512M";
      MemoryMax = "1G";
      OOMScoreAdjust = 500;
    };
  };
in
{
  options.nori.resourceTier = mkOption {
    type = types.attrsOf (
      types.enum [
        "critical"
        "important"
        "heavy"
        "decorative"
      ]
    );
    default = { };
    example = lib.literalExpression ''
      {
        caddy = "critical";
        ollama = "heavy";
        hermes-dashboard = "decorative";
      }
    '';
    description = ''
      Per-service resource tier. The unit name is the systemd
      service name without `.service`. Each tier maps to a cgroup
      limit profile (CPUWeight / MemoryHigh / MemoryMax /
      OOMScoreAdjust) defined inside this module. Services without
      an explicit declaration inherit no extra limits — they share
      the host's RAM and the OOMScoreAdjust default of 0.

      A future guard can require every long-running service to
      declare a tier (same shape as nori.backups). Not enforced yet
      — opt-in for the modules we actively care about first.
    '';
  };

  config = {
    # Apply each declared tier as serviceConfig overrides on the named
    # service. mkDefault so a service can still override individual
    # fields (e.g. heavy → "ollama needs MemoryHigh=16G specifically").
    systemd.services = lib.mapAttrs (_unit: tier: {
      serviceConfig = lib.mapAttrs (_: v: lib.mkDefault v) profiles.${tier};
    }) config.nori.resourceTier;

    # ── systemd-oomd: pressure-targeting safety valve ──────────────
    # When system memory pressure exceeds the configured threshold
    # oomd kills the cgroup contributing the most. Because heavy /
    # decorative tiers tend to be the ones generating pressure (large
    # model loads, web UIs), they're the natural targets — without
    # us having to tag specific units as "killable."
    services.systemd-oomd = {
      enable = true;
      enableRootSlice = true; # monitor system.slice (where homelab services run)
      enableUserSlices = true; # monitor user@1000.slice (hermes-dashboard etc.)
      enableSystemSlice = true;
    };
  };
}
