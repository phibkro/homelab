{
  config,
  lib,
  pkgs,
  ...
}:

{
  /*
    Defaults match the prod workstation shape; tests override to point
    at a stub receiver + a path that's controllable from the testScript.
    Other hosts that import this module can drop the mountpoint that
    only workstation has (`/mnt/media/library`).
  */
  options.nori.observability.diskAlert = {
    mountpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/"
        "/mnt/media/library"
      ];
      description = ''
        df --output=target,pcent reports by mountpoint. One mountpoint
        per btrfs filesystem is enough — any subvol mountpoint reads
        the same usage as the parent. Override on hosts that don't
        have all the prod mountpoints.
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
        guaranteed to fire on the VM's underlying filesystem.
      '';
    };
    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = ''
        Base URL the disk-alert script POSTs to. Channel name from
        sops appended as a path segment. Production points at ntfy.sh
        (where the operator's mobile app subscribes); tests redirect
        to an in-VM stub receiver.
      '';
    };
  };

  config = lib.mkMerge [
    { nori.services.disk-alert.tags = [ "observability" ]; }
    (lib.mkIf config.nori.services.disk-alert.enabled {
      /**
        disk-alert — periodic free-space watchdog. Fires an ntfy
        notification when any monitored filesystem crosses the critical
        threshold.

        WHY: btrbk retention works in the steady state (proven by the
        2026-05-14 incident's btrbk-media run pruning correctly once we'd
        freed space), but cannot make progress at 100% full — even
        subvolume delete needs metadata reserve. Combined with
        qBittorrent's deliberate incomplete-on-NVMe / complete-on-HDD
        split (qbittorrent.nix), a full @downloads silently wedges
        partials onto the SN750 until both drives are wedged.

        This module is the early-warning that catches that class of
        problem before services break.

        Why a separate posting script rather than reusing notify@: the
        template's message format is fixed to "Unit X failed on host"
        which is wrong for a disk-usage event. The curl-to-ntfy.sh
        pattern itself is shared with notify.nix.
      */

      systemd.services.disk-alert = {
        description = "Check disk free space and alert via ntfy if low";
        serviceConfig = {
          Type = "oneshot";
          User = "root"; # reads /run/secrets/ntfy-channel (mode 0444)
        };
        unitConfig.OnFailure = [ "notify@disk-alert.service" ];
        path = [
          pkgs.coreutils
          pkgs.curl
        ];
        script = ''
          set -eu
          CHANNEL=$(cat ${config.sops.secrets.ntfy-channel.path})

          df --output=target,pcent ${lib.concatStringsSep " " config.nori.observability.diskAlert.mountpoints} \
            | tail -n +2 \
            | while read -r mount pct_raw; do
                pct=''${pct_raw%\%}
                if [ "$pct" -ge ${toString config.nori.observability.diskAlert.criticalThresholdPct} ]; then
                  level=critical
                  prio=urgent
                  tags="rotating_light,sos"
                else
                  continue
                fi
                curl -fsS \
                  -H "Title: ${config.networking.hostName}: disk $level ($mount $pct%)" \
                  -H "Priority: $prio" \
                  -H "Tags: $tags" \
                  -d "Filesystem $mount on ${config.networking.hostName} is $pct% used. See docs/runbooks/storage-full.md." \
                  "${config.nori.observability.diskAlert.baseUrl}/$CHANNEL" || true
              done
        '';
      };

      systemd.timers.disk-alert = {
        description = "Periodic disk-alert check";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # 5 min after boot, then every 30 min. Cheap; df is one syscall.
          OnBootSec = "5min";
          OnUnitActiveSec = "30min";
          # If we miss runs (suspended laptop, etc.) don't fire a stampede.
          AccuracySec = "1min";
        };
      };

      nori.backups.disk-alert.skip = "Stateless — reads df and POSTs to ntfy on threshold breach.";

      /*
        df on any mountpoint under /mnt/* needs the path visible inside
        the namespace; the baseline `/mnt:ro` tmpfs would otherwise mask
        it. statfs() through a read-only bind reports the underlying
        btrfs usage correctly. Root mount (`/`) is unaffected by the
        baseline. ntfy-channel under /run/secrets stays reachable —
        /run isn't restricted by ProtectHome.
      */
      nori.harden.disk-alert = {
        readOnlyBinds = lib.filter (m: lib.hasPrefix "/mnt/" m) (
          config.nori.observability.diskAlert.mountpoints
        );
      };
    })
  ];
}
