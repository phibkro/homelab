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
  # @downloads is re-derivable; intentionally excluded from snapshots
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
  # deletion" recovery path per RECOVERY.md RTO targets (target: <15 min
  # to restore an accidentally-deleted file).
  #
  # Two instances, one per btrfs filesystem:
  #   root (SN750):    /home, /srv/share, /var/lib  → /.snapshots
  #   media (IronWolf): /mnt/media/{photos,...}     → /mnt/media/.snapshots
  #
  # Subvolume lists derived from nori.fs by tier filter (anything
  # `tier != re-derivable`); @var/lib added explicitly because it's
  # NixOS-managed StateDirectory, not a structural FS location.
  #
  # Subvolumes intentionally NOT snapshotted:
  #   @       (system root — covered by NixOS generations)
  #   @nix    (re-derivable from the flake)
  #   @downloads (re-derivable per DESIGN tier table — filtered out)
  #
  # Retention conservative for first run; tune per disk growth.

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

  # Alert via ntfy template in modules/server/ntfy/notify.nix.
  systemd.services.btrbk-root.unitConfig.OnFailure = [ "notify@btrbk-root.service" ];
  systemd.services.btrbk-media.unitConfig.OnFailure = [ "notify@btrbk-media.service" ];

  # ── btrfs qgroup quota on @downloads ────────────────────────────
  # Cap @downloads at 3.3 TiB on the IronWolf (3.64 TiB total) to
  # prevent the 100%-full metadata-exhaustion wedge pattern (see
  # docs/runbooks/storage-full.md). At 100% btrfs can't even reclaim
  # via subvolume delete because metadata writes need reserve — that's
  # the actual recovery-hostile failure mode, not "disk full" itself.
  #
  # With the cap: qBit-as-writer hits ENOSPC on the @downloads quota
  # well before the filesystem hits the metadata wall. Recovery path
  # stays open (delete from @downloads to free; quota doesn't apply
  # to the system pool's metadata budget).
  #
  # Headroom math (snapshot 2026-05-16): @downloads = 3.2 TiB, other
  # subvols = 462 GiB, total used ~3.66 TiB on a 3.64 TiB drive (the
  # drive itself is the bottleneck). 3.3 TiB cap allows ~100 GiB more
  # in-flight downloads to land before qBit stalls; the other 365 GiB
  # of @downloads headroom on the drive stays available for the other
  # subvols (photos growth especially).
  #
  # Tune via the 3300G literal below. Adjust upward if the other
  # subvols grow such that the budget for @downloads needs to shrink.
  #
  # btrfs qgroup overhead: ~5% on metadata-heavy ops (modifying CoW
  # ref counts on every write). Acceptable cost for the wedge guard
  # on a non-CPU-bound media drive.
  #
  # Activation runs on every nixos-rebuild switch. `quota enable` is
  # idempotent (no-op if already on). `qgroup limit` overwrites the
  # existing limit cleanly. First-time enable triggers a rescan that
  # may run for an hour on the multi-TiB filesystem; the limit takes
  # effect after rescan completes.
  #
  # IMPORTANT — target path: /mnt/media itself is NOT a mountpoint
  # (each subvol mounts directly under it: /mnt/media/{downloads,
  # photos,...}). Targeting /mnt/media resolves to the root filesystem
  # (SN750) and enables quotas there — wrong FS, expensive. Use a real
  # IronWolf mountpoint instead. /mnt/media/downloads is the canonical
  # choice (it's the subvol we're capping anyway). subvolume list also
  # needs a real mountpoint to enumerate.
  system.activationScripts.btrfs-quota-media.text = ''
    ${pkgs.btrfs-progs}/bin/btrfs quota enable /mnt/media/downloads >/dev/null 2>&1 || true
    downloads_id=$(${pkgs.btrfs-progs}/bin/btrfs subvolume list /mnt/media/downloads \
      | ${pkgs.gawk}/bin/awk '$NF == "@downloads" { print $2 }')
    if [ -n "$downloads_id" ]; then
      ${pkgs.btrfs-progs}/bin/btrfs qgroup limit 3300G "0/$downloads_id" /mnt/media/downloads \
        || echo "WARNING: failed to set @downloads quota (rescan in progress?)"
    fi
  '';
}
