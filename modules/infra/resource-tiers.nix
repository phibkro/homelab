{
  config,
  lib,
  ...
}:

/**
  Resource tiers — per-service cgroup limits + systemd-oomd pressure
  valve. Without this, a single mis-behaving service balloons and the
  kernel OOM-killer picks targets by oom_score_adj — often killing
  Caddy or sshd while the offender survives.
*/

let
  inherit (lib) mkOption types;

  # Numbers calibrated for a ~64 GB workstation. Tune per host if its
  # RAM differs by an order of magnitude.
  profiles = {
    critical = {
      CPUWeight = 1000;
      IOWeight = 1000;
      # No MemoryHigh by design — critical services get the whole
      # host's RAM if they need it. Goal is ALIVE, not shaped.
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
      Per-service resource tier. Key = systemd unit name without
      `.service`.

      * `critical`   — keep alive at all costs (caddy, blocky, authelia,
                       sshd, tailscaled, notify@). No memory cap; top
                       CPUWeight; OOMScoreAdjust = -500.
      * `important`  — needs to stay up under normal load; reclaimable
                       under real pressure (beszel, gatus, immich-server,
                       jellyfin, vaultwarden).
      * `heavy`      — known-large RAM users; first OOM target after
                       decorative (ollama, immich-ml, open-webui).
      * `decorative` — nice-to-have; first reclaimed (dashboard-style
                       services). OOMScoreAdjust = 500.

      Services without a tier inherit no extra limits + default
      OOMScoreAdjust 0. Future: a flake check requiring explicit
      declaration for every long-running service (mirrors
      `every-service-has-backup-intent`).
    '';
  };

  config = {
    # mkDefault so services can override individual fields (e.g.
    # ollama needs MemoryHigh=16G specifically inside "heavy").
    systemd.services = lib.mapAttrs (_unit: tier: {
      serviceConfig = lib.mapAttrs (_: v: lib.mkDefault v) profiles.${tier};
    }) config.nori.resourceTier;

    /*
      systemd-oomd targets cgroups by PSI pressure contribution, not
      by oom_score_adj. Heavy/decorative tend to be the pressure
      source, so they get killed before critical units do.
    */
    services.systemd-oomd = {
      enable = true;
      enableRootSlice = true;
      enableUserSlices = true;
      enableSystemSlice = true;
    };
  };
}
