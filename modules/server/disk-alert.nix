{
  config,
  lib,
  pkgs,
  ...
}:

let
  # One mountpoint per btrfs filesystem we care about. df reports by
  # mountpoint, but any mountpoint on a given filesystem reads the
  # same usage — so we only need one per FS, not one per subvol.
  #
  #   /                  → SN750 NVMe (workstation root, all subvols)
  #   /mnt/media/library → IronWolf (any media subvol works equivalently)
  mountpoints = [
    "/"
    "/mnt/media/library"
  ];

  # Thresholds chosen to leave btrbk + qBittorrent enough headroom to
  # operate. At 85% on root we still have ~140 GiB free; at 85% on
  # media ~550 GiB. That's lead time to cull or reconfigure before
  # qBittorrent's incomplete-on-NVMe wedge (see qbittorrent.nix) can
  # form. 95% is the last call before btrfs metadata pressure starts
  # failing operations including snapshot deletes — past that point
  # recovery gets harder (see docs/runbooks/storage-full.md).
  warnPct = 85;
  critPct = 95;
in
{
  # disk-alert — periodic free-space watchdog. Fires an ntfy
  # notification when any monitored filesystem crosses warn or
  # critical thresholds.
  #
  # WHY: btrbk retention works in the steady state (proven by the
  # 2026-05-14 incident's btrbk-media run pruning correctly once we'd
  # freed space), but cannot make progress at 100% full — even
  # subvolume delete needs metadata reserve. Combined with
  # qBittorrent's deliberate incomplete-on-NVMe / complete-on-HDD
  # split (qbittorrent.nix), a full @downloads silently wedges
  # partials onto the SN750 until both drives are wedged.
  #
  # This module is the early-warning that catches that class of
  # problem before services break.
  #
  # Why a separate posting script rather than reusing notify@: the
  # template's message format is fixed to "Unit X failed on host"
  # which is wrong for a disk-usage event. The curl-to-ntfy.sh
  # pattern itself is shared with notify.nix.

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

      df --output=target,pcent ${lib.concatStringsSep " " mountpoints} \
        | tail -n +2 \
        | while read -r mount pct_raw; do
            pct=''${pct_raw%\%}
            if [ "$pct" -ge ${toString critPct} ]; then
              level=critical
              prio=urgent
              tags="rotating_light,sos"
            elif [ "$pct" -ge ${toString warnPct} ]; then
              level=warning
              prio=high
              tags="warning"
            else
              continue
            fi
            curl -fsS \
              -H "Title: ${config.networking.hostName}: disk $level ($mount $pct%)" \
              -H "Priority: $prio" \
              -H "Tags: $tags" \
              -d "Filesystem $mount on ${config.networking.hostName} is $pct% used. See docs/runbooks/storage-full.md." \
              "https://ntfy.sh/$CHANNEL" || true
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

  # Stateless — no on-disk state to back up.
  nori.backups.disk-alert.skip = "Stateless — reads df and POSTs to ntfy.sh on threshold breach.";

  # df on /mnt/media/library needs the mountpoint visible inside the
  # namespace; the baseline `/mnt:ro` tmpfs would otherwise mask it.
  # statfs() through a read-only bind reports the underlying btrfs
  # usage correctly. Root mount (`/`) is unaffected by the baseline.
  # ntfy-channel under /run/secrets stays reachable — /run isn't
  # restricted by ProtectHome.
  nori.harden.disk-alert = {
    readOnlyBinds = [ "/mnt/media/library" ];
  };
}
