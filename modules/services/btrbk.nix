{
  config,
  lib,
  pkgs,
  ...
}:

{
  # btrbk — local btrfs subvolume snapshots, the "single file
  # deletion" recovery path per DESIGN.md RTO table (target: <15 min
  # to restore an accidentally-deleted file).
  #
  # Two instances, one per btrfs filesystem:
  #   root (SN750):    /home, /srv/share, /var/lib  → /.snapshots
  #   media (IronWolf): /mnt/media/{photos,home-videos,projects} → /mnt/media/.snapshots
  #
  # Subvolumes intentionally NOT snapshotted:
  #   @       (the system root — covered by NixOS generations)
  #   @nix    (re-derivable from the flake)
  #   @streaming (re-derivable per DESIGN tier table)
  #
  # Retention is conservative for first run; tighten/loosen per
  # actual disk growth observation. DESIGN's L113-138 retention
  # targets:
  #   @home: hourly + daily          ← starting daily-only; bump to
  #                                     hourly later if churn warrants
  #   @var-lib, @srv-share: daily
  #   @photos: daily 14 + monthly 12
  #   @home-videos, @projects: weekly, keep 4
  #
  # btrbk's onCalendar fires the snapshot job. Retention is enforced
  # on each run via snapshot_preserve.

  services.btrbk = {
    instances.root = {
      onCalendar = "daily";
      settings = {
        snapshot_preserve_min = "2d";
        snapshot_preserve = "7d 4w 6m";
        snapshot_dir = ".snapshots";
        timestamp_format = "long";
        volume."/" = {
          subvolume = {
            "home" = { };
            "srv/share" = { };
            "var/lib" = { };
          };
        };
      };
    };

    instances.media = {
      onCalendar = "daily";
      settings = {
        snapshot_preserve_min = "2d";
        snapshot_preserve = "14d 8w 12m";
        snapshot_dir = ".snapshots";
        timestamp_format = "long";
        volume."/mnt/media" = {
          subvolume = {
            "photos" = { };
            "home-videos" = { };
            "projects" = { };
          };
        };
      };
    };
  };

  # btrbk needs btrfs-progs for snapshot creation; the module pulls
  # it in automatically.

  # Alert on snapshot job failure via ntfy template in
  # modules/services/ntfy.nix.
  systemd.services.btrbk-root.unitConfig.OnFailure = [ "notify@btrbk-root.service" ];
  systemd.services.btrbk-media.unitConfig.OnFailure = [ "notify@btrbk-media.service" ];
}
