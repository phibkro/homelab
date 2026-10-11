{
  config,
  lib,
  pkgs,
  ...
}:

/**
  Storage concern — filesystem allocation pressure.

  One construct measures and classifies allocation pressure so the alarm,
  the snapshot guard and bounded maintenance cannot disagree about what
  "critical" means. `package` exposes the measurement CLI; `enable` adds
  the package on PATH and schedules the bounded maintenance run.

  The CLI (implementation in `pressure-cli.bash`, built here):

      nori-storage-pressure probe PATH       # JSON measurement + state
      nori-storage-pressure check PATH       # 0 healthy|warning, 75 critical, 1 error
      nori-storage-pressure with-lock PATH CMD...   # 75 when the lock is busy
      nori-storage-pressure maintain PATH... # bounded data-only compaction

  `probe`/`check` print
  `{path, fs_type, fs_uuid, ordinary_used_pct, metadata_used_bytes,
    metadata_total_bytes, metadata_used_pct, unallocated_bytes, state}`
  where the btrfs-specific fields (and `fs_uuid`) are null for a non-btrfs
  filesystem, and `state` is healthy | warning | critical. Any failed,
  missing or self-inconsistent measurement exits nonzero and never reports
  a healthy filesystem.

  Classification, with all thresholds from `nori.storagePressure`:
  critical when ordinary usage reaches its threshold (the alarm's existing
  rule) or when metadata usage is at/above critical AND unallocated device
  space is at/below the critical workspace; warning when metadata usage is
  at/above the warning threshold AND unallocated space is below the warning
  workspace. High metadata with adequate expansion workspace is not
  critical. Non-btrfs filesystems keep ordinary-space semantics only.

  Locks are per physical filesystem, keyed by btrfs UUID (device number
  otherwise), under `lockDir`; the snapshot writer shares the same lock by
  overriding `lockGroup` to its own group, so allocation maintenance and a
  snapshot never overlap on one filesystem.

  Maintenance is data-only and bounded: reclaim empty data block groups
  first, then — only when unallocated space is below the headroom target and
  workspace remains to compact safely — one balance limited by `usage` and
  `limit`. It defers while another exclusive filesystem operation (or the
  lock) owns the filesystem, refuses further compaction when workspace is
  exhausted, and never runs a full balance, a metadata profile conversion,
  or any deletion.
  Workspace refusal returns 75 (EX_TEMPFAIL), accepted by the maintenance
  unit. Any real error returns 1 and takes precedence across filesystems.
  Otherwise it returns 0, including existing owner/lock deferrals.
*/
let
  cfg = config.nori.storagePressure;

  inherit (lib)
    mkOption
    types
    mkIf
    escapeShellArg
    escapeShellArgs
    ;

  giB = 1024 * 1024 * 1024;

  /*
    The package bakes the policy into the script's environment, so the
    script body never repeats a threshold and `nori.storagePressure` stays
    the single source. The `NORI_PRESSURE_STAT` / `_BTRFS` / `_SYSFS_BTRFS`
    seams are UNSET here: they exist only for tests that assemble
    `pressure-cli.bash` directly, so no caller environment can displace the
    pinned runtimeInputs or the kernel's exclusive-operation counter.
  */
  package = pkgs.writeShellApplication {
    name = "nori-storage-pressure";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.btrfs-progs
      pkgs.util-linux
      pkgs.jq
    ];
    text = ''
      unset NORI_PRESSURE_STAT NORI_PRESSURE_BTRFS NORI_PRESSURE_SYSFS_BTRFS

      export NORI_PRESSURE_METADATA_WARNING_PCT=${toString cfg.metadataWarningPct}
      export NORI_PRESSURE_METADATA_CRITICAL_PCT=${toString cfg.metadataCriticalPct}
      export NORI_PRESSURE_WARNING_WORKSPACE_BYTES=${toString (cfg.warningWorkspaceGiB * giB)}
      export NORI_PRESSURE_CRITICAL_WORKSPACE_BYTES=${toString (cfg.criticalWorkspaceGiB * giB)}
      export NORI_PRESSURE_ORDINARY_CRITICAL_PCT=${toString cfg.ordinaryCriticalPct}
      export NORI_PRESSURE_LOCK_DIR=${escapeShellArg cfg.lockDir}
      export NORI_PRESSURE_LOCK_GROUP=${escapeShellArg cfg.lockGroup}
      export NORI_PRESSURE_MAINTENANCE_USAGE=${toString cfg.maintenance.usage}
      export NORI_PRESSURE_MAINTENANCE_LIMIT=${toString cfg.maintenance.limit}
      export NORI_PRESSURE_HEADROOM_TARGET_BYTES=${toString (cfg.maintenance.headroomTargetGiB * giB)}
      ${builtins.readFile ./pressure-cli.bash}
    '';
  };
in
{
  options.nori.storagePressure = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install the pressure construct (package on PATH + bounded
        maintenance service/timer). `package` exists regardless, so a
        consumer that only needs `check`/`with-lock` does not have to enable
        maintenance. The disk-alert workload module enables this on the
        workstation.
      '';
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      default = package;
      description = ''
        The pressure CLI derivation: `bin/nori-storage-pressure` with the
        `probe`/`check`/`with-lock`/`maintain` subcommands described in this
        file's overview.
      '';
    };

    paths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Filesystem paths to maintain. Subvolume paths on one physical
        filesystem are maintained once — paths are deduplicated by
        filesystem identity (btrfs UUID, device number otherwise), never by
        mountpoint. Non-btrfs paths are reported and skipped.
      '';
    };

    metadataWarningPct = mkOption {
      type = types.ints.between 1 99;
      default = 85;
      description = "Metadata usage percentage that starts warning while expansion workspace is scarce.";
    };

    metadataCriticalPct = mkOption {
      type = types.ints.between 1 99;
      default = 95;
      description = "Metadata usage percentage that is critical when expansion workspace is also exhausted.";
    };

    warningWorkspaceGiB = mkOption {
      type = types.ints.positive;
      default = 20;
      description = ''
        Unallocated device space below which metadata usage at/above
        `metadataWarningPct` warns. At or above this much expansion space,
        high metadata utilization is not a warning.
      '';
    };

    criticalWorkspaceGiB = mkOption {
      type = types.ints.positive;
      default = 2;
      description = ''
        Unallocated device space at/below which metadata usage at/above
        `metadataCriticalPct` is critical — the filesystem has run out of
        room to allocate new metadata chunks.
      '';
    };

    ordinaryCriticalPct = mkOption {
      type = types.ints.between 1 99;
      default = 95;
      description = ''
        Ordinary-space critical threshold, carried from
        `nori.observability.diskAlert.criticalThresholdPct` by the disk-alert
        module so the alarm keeps one threshold, not two.
      '';
    };

    lockDir = mkOption {
      type = types.str;
      default = "/run/lock/nori-storage-pressure";
      description = "Directory holding the per-filesystem lock files.";
    };

    lockGroup = mkOption {
      type = types.str;
      default = "root";
      description = ''
        Group owning the lock directory and lock files (mode 0770/0660), so
        a non-root snapshot writer can share the per-filesystem lock. The
        btrbk snapshot writer sets this to its own group and adds that group
        to the writer's supplementary groups.
      '';
    };

    maintenance = mkOption {
      default = { };
      description = "Bounds for the scheduled maintenance run.";
      type = types.submodule {
        options = {
          usage = mkOption {
            type = types.ints.between 1 100;
            default = 10;
            description = ''
              Data block groups below this utilization are compacted by the
              second pass (`btrfs balance start -dusage=<usage>
              -dlimit=<limit>`). Only reached when unallocated space is
              below `headroomTargetGiB` and workspace remains.
            '';
          };
          limit = mkOption {
            type = types.ints.positive;
            default = 4;
            description = "Maximum block groups each balance pass processes per run — the finite work budget.";
          };
          headroomTargetGiB = mkOption {
            type = types.ints.positive;
            default = 32;
            description = ''
              Target unallocated device space. At or above it, the run stops
              after reclaiming empty block groups; below it, the bounded
              compaction pass runs if workspace remains.
            '';
          };
          interval = mkOption {
            type = types.str;
            default = "1h";
            description = "Timer interval between maintenance runs (systemd time span).";
          };
        };
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [
      "d ${cfg.lockDir} 0770 root ${cfg.lockGroup} -"
    ];

    # Hourly timer, matching the shape the other periodic checks use. No
    # pressure-awake trigger: the alarm's frequent poll already reports a
    # climbing filesystem, and maintenance is a background reclaim, not an
    # incident response.
    systemd.services.nori-storage-pressure-maintain = mkIf (cfg.paths != [ ]) {
      description = "Bounded btrfs allocation maintenance (empty block-group reclaim + limited data compaction)";
      /*
        Deliberately NOT registered in `nori.harden`: the run must act on the
        real mounts (a read-only bind namespace view is the wrong object for
        a balance), and it needs /run/lock to serialize with the snapshot
        writer. It runs as root because balance is a privileged ioctl.
      */
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        SuccessExitStatus = [ 75 ];
      };
      unitConfig.OnFailure = [ "notify@nori-storage-pressure-maintain.service" ];
      script = ''
        exec ${cfg.package}/bin/nori-storage-pressure maintain ${escapeShellArgs cfg.paths}
      '';
    };

    systemd.timers.nori-storage-pressure-maintain = mkIf (cfg.paths != [ ]) {
      description = "Periodic bounded btrfs allocation maintenance";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15min";
        OnUnitActiveSec = cfg.maintenance.interval;
        # If a run is missed (suspended laptop), don't fire a stampede.
        AccuracySec = "5min";
      };
    };
  };
}
