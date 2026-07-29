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

  !!! CURRENTLY IMPORTED BY NO HOST — THIS FILE IS INERT !!!

  Verified 2026-07-30: `grep -rn resource-tiers --include=.nix .` matches
  nothing, and `nori.resourceTier` is absent from `config.nori` on every host
  (workstation and aurora both checked via `nix eval`). Nothing below has
  ever taken effect on any machine.

  Why it went unnoticed for so long: the flake's completeness lint globs
  `modules/infra/<X>/default.nix` (flake.nix ~1088) to find concerns that
  declare `options.nori.*`. This is a FLAT file, so it is invisible to
  that check — the lint can only catch a directory-shaped concern that
  forgot a recipe, never a module nobody imports.

  Consequence, paid on 2026-07-30: no system service has a memory ceiling,
  so an unbounded `nix build` drove the box into swap thrash and oomd
  culled 211 agent processes instead (docs/reports/
  2026-07-30-nix-build-memory-saturation.md). The immediate ceiling now
  lives host-scoped in machines/workstation/default.nix; this module
  remains the right home for the GENERAL case.

  Two honest resolutions, both a real decision rather than a cleanup:
    1. adopt — import it per host and assign tiers to the long-running
       services (note `enableRootSlice` sets ManagedOOMSwap=kill on the
       ROOT slice, which changes behaviour for everything; adopt that flag
       deliberately, not incidentally), and recalibrate the numbers below
       (they say "~64 GB workstation"; workstation actually has 31 GiB).
    2. delete — if the per-host approach is preferred, remove the file so
       it stops reading as an active guarantee.
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
        glance = "decorative";
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
    /*
      Option path corrected 2026-07-30: this block read
      `services.systemd-oomd` — an option that does not exist. The real
      path is `systemd.oomd` (what workstation/default.nix already uses).
      The mistake never surfaced as an eval error only because the module
      is imported nowhere, so this `config` block is never evaluated;
      adopting the file with the old path would have failed immediately
      with "option does not exist".

      Live proof the intent never landed: `systemd.oomd.enableSystemSlice`
      and `enableRootSlice` both evaluate to `false` on workstation, no
      /etc/systemd/system/system.slice.d drop-in exists, and `oomctl`
      monitors only /user.slice and its descendants.
    */
    systemd.oomd = {
      enable = true;
      enableRootSlice = true;
      enableUserSlices = true;
      enableSystemSlice = true;
    };
  };
}
