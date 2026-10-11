{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.observability.diskAlert;
  inherit (config.nori) storagePressure;
in
{
  /*
    Defaults match the production workstation storage shape; tests override these
    with a stub receiver and a controllable path. Other hosts can replace the
    list when they do not mount the workstation destinations.
  */
  options.nori.observability.diskAlert = {
    mountpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/"
        "/mnt/backup"
        "/mnt/backup-local"
        "/mnt/media/library"
      ];
      description = ''
        One mountpoint per physical filesystem; any subvolume mountpoint
        reports the same allocation numbers as its parent, and maintenance
        deduplicates paths by filesystem identity. Override on hosts that
        don't have all the prod mountpoints.
      '';
    };
    mutedCriticalMountpoints = lib.mkOption {
      type = lib.types.listOf (lib.types.enum cfg.mountpoints);
      default = [ ];
      description = ''
        Monitored mountpoints whose critical notifications are muted.
        Measurements, warnings, measurement errors, maintenance, and snapshot guards remain enabled.
      '';
    };
    criticalThresholdPct = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 95;
      description = ''
        Single critical threshold. 95% is the last call before btrfs
        metadata pressure starts failing operations including snapshot
        deletes — past that point recovery gets harder (see
        docs/runbooks/storage-full.md). Tests override to a low %
        guaranteed to fire on the VM's underlying filesystem. Carried into
        `nori.storagePressure.ordinaryCriticalPct` so the shared
        measurement classifies against this one threshold.
      '';
    };
    # Delivery (channel + baseUrl) now lives on nori.alerts; disk-alert
    # just emits an `operator` alert. Tests override the infra channel's
    # baseUrl via nori.observability.ntfyNotify.baseUrl.
  };

  config = {
    /*
      Wire the shared pressure construct this alarm measures through, keeping
      one policy source: the monitored paths and the ordinary critical
      threshold are disk-alert's own options, carried into
      `nori.storagePressure` rather than copied. Enabling it here is the
      workstation opt-in (the disk-alert workload module is selected only
      there); the maintenance run targets the same filesystems.
    */
    nori.storagePressure = {
      enable = lib.mkDefault true;
      paths = lib.mkDefault cfg.mountpoints;
      ordinaryCriticalPct = lib.mkDefault cfg.criticalThresholdPct;
    };

    /**
      disk-alert — periodic allocation-pressure watchdog. Fires an ntfy
      notification when any monitored filesystem crosses the critical
      threshold, warns once when a filesystem enters the warning band, and
      treats an unmeasurable filesystem as an error.

      WHY: btrbk retention works in the steady state (proven by the
      2026-05-14 incident's btrbk-media run pruning correctly once we'd
      freed space), but cannot make progress at 100% full — even
      subvolume delete needs metadata reserve. Combined with
      qBittorrent's deliberate incomplete-on-NVMe / complete-on-HDD
      split (qbittorrent.nix), a full @downloads silently wedges
      partials onto the SN750 until both drives are wedged.

      This module is the early-warning that catches that class of
      problem before services break. Measurement, classification and the
      alert policy live in the storage concern's pressure package /
      pressure-alarm.bash, so the alarm, the snapshot guard and the bounded
      maintenance run cannot disagree about what "critical" means.

      It emits through nori.alerts (`operator` audience) — the same
      emit-point notify@ uses. The event differs (a disk threshold, not
      a unit failure) but the delivery path is one construct now.
    */

    systemd.services.disk-alert = {
      description = "Check filesystem allocation pressure and alert via ntfy if critical";
      serviceConfig = {
        Type = "oneshot";
        User = "root"; # nori-alert reads /run/secrets/ntfy-channel (mode 0444)
        /*
          Warning stamps live in the unit's runtime directory and must survive
          between oneshot runs: without `RuntimeDirectoryPreserve` the
          directory is removed on exit and the same warning would re-alert
          every poll.
        */
        RuntimeDirectory = "disk-alert";
        RuntimeDirectoryPreserve = "yes";
      };
      unitConfig.OnFailure = [ "notify@disk-alert.service" ];
      path = [
        pkgs.coreutils
        pkgs.jq
      ];
      script = ''
        set -euo pipefail

        export PRESSURE_CLI=${storagePressure.package}/bin/nori-storage-pressure
        export PRESSURE_ALERT_CMD=${config.nori.alerts.command}
        export PRESSURE_HOST=${config.networking.hostName}
        export PRESSURE_STATE_DIR=$RUNTIME_DIRECTORY
        export PRESSURE_MUTED_CRITICAL_MOUNTPOINTS=${lib.escapeShellArg (builtins.toJSON cfg.mutedCriticalMountpoints)}
        export PRESSURE_META_WARN_PCT=${toString storagePressure.metadataWarningPct}
        export PRESSURE_META_CRIT_PCT=${toString storagePressure.metadataCriticalPct}
        export PRESSURE_WARN_WORKSPACE_BYTES=${
          toString (storagePressure.warningWorkspaceGiB * 1024 * 1024 * 1024)
        }
        export PRESSURE_CRIT_WORKSPACE_BYTES=${
          toString (storagePressure.criticalWorkspaceGiB * 1024 * 1024 * 1024)
        }

        # Alarm policy (critical alert, once-per-episode warning, measurement
        # failure is an error) lives beside the CLI it drives.
        ${builtins.readFile ../../infra/common/nixos/storage/pressure-alarm.bash}

        main ${lib.escapeShellArgs cfg.mountpoints}
      '';
    };

    systemd.timers.disk-alert = {
      description = "Periodic disk-alert check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # 5 min after boot, then every 5 min: one statfs call per mountpoint,
        # plus the btrfs allocation query on btrfs, so a climbing filesystem
        # is caught while allocation workspace remains to act on.
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        # If we miss runs (suspended laptop, etc.) don't fire a stampede.
        AccuracySec = "1min";
      };
    };

    nori.backups.disk-alert.skip = "Stateless — measures statfs + btrfs allocation and POSTs to ntfy on threshold breach. Its runtime directory holds warning stamps, not data.";

    /*
      Read-only bind visibility: services run in a namespace where the
      baseline overlays /mnt and /srv as read-only tmpfs, so any configured
      mountpoint under either prefix must be bound back in explicitly.
      statfs() through a read-only bind reports the underlying usage
      correctly, and the btrfs allocation queries are read-only ioctls —
      verified through a `ro,bind` mount in an isolated mount namespace
      (2026-10-07). Root mount (`/`) is unaffected by the baseline.
      ntfy-channel under /run/secrets stays reachable — /run isn't restricted
      by ProtectHome.
    */
    nori.harden.disk-alert = {
      readOnlyBinds = lib.filter (m: lib.hasPrefix "/mnt/" m || lib.hasPrefix "/srv/" m) cfg.mountpoints;
    };
  };
}
