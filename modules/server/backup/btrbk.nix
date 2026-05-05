{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Subvolume keys for btrbk's `volume."X".subvolume` are paths
  # *relative to the volume root*. Derive them from nori.fs by
  # stripping the volume-root prefix; entries under /mnt/media live
  # on the media volume, the rest live on the root volume.
  inherit (config.nori) fs;

  onMedia = _: f: lib.hasPrefix "/mnt/media/" f.path;
  onRoot = n: f: !(onMedia n f); # everything not under /mnt/...
  # @streaming is re-derivable; intentionally excluded from snapshots
  # (DESIGN tier table). Filter `re-derivable` tier out.
  isSnapshotted = _: f: f.tier != "re-derivable";

  rootSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/" f.path) { }) (
    lib.filterAttrs (n: f: onRoot n f && isSnapshotted n f) fs
  );

  mediaSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/mnt/media/" f.path) { }) (
    lib.filterAttrs (n: f: onMedia n f && isSnapshotted n f) fs
  );
in
{
  # btrbk — local btrfs subvolume snapshots, the "single file
  # deletion" recovery path per DESIGN.md RTO table (target: <15 min
  # to restore an accidentally-deleted file).
  #
  # Two instances, one per btrfs filesystem:
  #   root (SN750):    /home, /srv/share, /var/lib  → /.snapshots
  #   media (IronWolf): /mnt/media/{photos,...}     → /mnt/media/.snapshots
  #
  # Subvolume lists are derived from nori.fs (host's disko config is
  # the single source of truth). Anything with `tier != re-derivable`
  # gets snapshotted; @streaming and similar are excluded by tier
  # filter rather than enumeration. @var/lib is added explicitly —
  # it's a btrfs subvolume but not in nori.fs (StateDirectory paths
  # are NixOS-managed, not a structural FS location services consume).
  #
  # Subvolumes intentionally NOT snapshotted:
  #   @       (the system root — covered by NixOS generations)
  #   @nix    (re-derivable from the flake)
  #   @streaming (re-derivable per DESIGN tier table — filtered out)
  #
  # @archive — historical/cold data (legacy machine backups etc.).
  # Snapshot daily, retain per the media instance's retention curve;
  # the data is mostly immutable so daily snapshots are nearly-free.
  #
  # @library — curated media (books, comics). Daily snapshot, included
  # in restic media-irreplaceable.
  #
  # Retention is conservative for first run; tighten/loosen per
  # actual disk growth observation. DESIGN's retention targets:
  #   @home: hourly + daily          ← starting daily-only; bump to
  #                                     hourly later if churn warrants
  #   @var-lib, @srv-share: daily
  #   @photos: daily 14 + monthly 12
  #   @home-videos, @projects: daily / weekly retention
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
          # rootSubvols has `home` + `srv/share` from nori.fs (user
          # tier). var/lib is a btrfs subvolume but not in nori.fs
          # (StateDirectory paths are NixOS-managed, not a structural
          # FS location services consume) — added explicitly.
          subvolume = rootSubvols // {
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
        volume."/mnt/media".subvolume = mediaSubvols;
      };
    };
  };

  # btrbk needs btrfs-progs for snapshot creation; the module pulls
  # it in automatically.

  # Alert on snapshot job failure via ntfy template in
  # modules/server/ntfy/notify.nix.
  systemd.services.btrbk-root.unitConfig.OnFailure = [ "notify@btrbk-root.service" ];
  systemd.services.btrbk-media.unitConfig.OnFailure = [ "notify@btrbk-media.service" ];
}
