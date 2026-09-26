{
  config,
  lib,
  pkgs,
  ...
}:

let
  /*
    Classify nori.fs paths by their physical btrfs namespace. Family
    paths must never fall through to the root namespace: their source
    filesystem is the Toshiba vault mounted at /mnt/family.
  */
  inherit (config.nori) fs;

  onMedia = _: f: lib.hasPrefix "/mnt/media/" f.path;
  onFamily = _: f: lib.hasPrefix "/mnt/family/" f.path;
  onRoot = n: f: !(onMedia n f) && !(onFamily n f);
  # @downloads is re-derivable; intentionally excluded from snapshots.
  isSnapshotted = _: f: f.tier != "re-derivable";

  rootSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/" f.path) { }) (
    lib.filterAttrs (n: f: onRoot n f && isSnapshotted n f) fs
  );

  mediaSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/mnt/media/" f.path) { }) (
    lib.filterAttrs (n: f: onMedia n f && isSnapshotted n f) fs
  );

  familySubvols = lib.mapAttrs' (
    _: f: lib.nameValuePair (lib.removePrefix "/mnt/family/" f.path) { }
  ) (lib.filterAttrs (n: f: onFamily n f && f.tier == "irreplaceable") fs);

  /*
    Root snapshots also leave the system NVMe: the IronWolf's @snapshots
    subvolume (mounted beside the media snapshots) receives them with
    btrbk send/receive. The target is a directory, not a nori.fs entry,
    because nori.fs tiers select what the snapshot and restic generators
    protect; this directory is their output. Mode 0700 keeps received
    /home and /var/lib copies out of the Samba `media` share and
    Jellyfin's read-only /mnt/media view.
  */
  rootRetention = config.nori.inventory.backup.retention.workstationRoot;
  ironwolf = config.nori.inventory.disks."ironwolf-pro";
  ironwolfSnapshots = "${ironwolf.mountPoint}/.snapshots";
  rootTarget = "${ironwolfSnapshots}/workstation-root";
in
/*
  Selected only by the Workstation `backup-source` system profile. btrbk
  snapshots the workstation's root, optional non-re-derivable media
  subvolumes, and the family vault; the activation script also enables
  the btrfs quota on /mnt/media/downloads.
*/
{
  /**
    btrbk — same-disk rollback snapshots, not independent backups.
    These provide the "single file
    deletion" recovery path per RECOVERY.md RTO targets (target: <15 min
    to restore an accidentally-deleted file).

    Instances are split by physical btrfs namespace:
      root (SN750):       /home, /srv/share, /srv/nori, /var/lib → /.snapshots
                          sent to /mnt/media/.snapshots/workstation-root
      media (IronWolf):   non-re-derivable /mnt/media/* → /mnt/media/.snapshots
      family (Toshiba):   irreplaceable /mnt/family/* → /mnt/family/.snapshots

    The media instance is declared only when nori.fs has a non-re-derivable
    media entry. The family filter is explicit so family paths can never
    become root subvolume names.

    @var/lib is added explicitly because it is a NixOS-managed StateDirectory,
    not a structural FS location. Intentionally excluded:
      @       (system root — covered by NixOS generations)
      @nix    (re-derivable from the flake)
      @downloads (re-derivable — filtered out)

    Root keeps one week on the system NVMe, where retained history
    competes with live data. The IronWolf receives every run as a
    read-only snapshot: off the system disk, still inside the workstation,
    so restic to the OneTouch remains the independent backup. The target
    starts with the latest snapshot only and moves to weekly/monthly
    history in a dated second phase; both values and the switch rule live
    in `retention.workstationRoot` in `src/inventory/backup.nix`.

    Family keeps its existing window. Cold media has a shorter window: it
    is mostly append-only archives, and local snapshots are an
    accidental-deletion tool rather than an independent backup. Keeping
    years of deleted media on the already-near-capacity IronWolf defeats
    that distinction.
  */
  services.btrbk = {
    instances = {
      root = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = rootRetention.localSnapshotPreserve;
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/" = {
            /*
              `latest` sends every daily snapshot, so the IronWolf copy is
              at most one run old. `target_preserve` selects which older
              received snapshots stay there ("no" in phase 1).
            */
            target.${rootTarget} = {
              target_preserve_min = "latest";
              target_preserve = rootRetention.ironwolfTargetPreserve;
            };
            /*
              rootSubvols has `home` + `srv/share` from nori.fs (user
              tier). var/lib is a btrfs subvolume but not in nori.fs
              (StateDirectory paths are NixOS-managed, not a structural
              FS location services consume) — added explicitly.
            */
            subvolume = rootSubvols // {
              "var/lib" = { };
            };
          };
        };
      };
    }
    // lib.optionalAttrs (familySubvols != { }) {
      family = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = "14d 8w 12m";
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/mnt/family".subvolume = familySubvols;
        };
      };
    }
    // lib.optionalAttrs (mediaSubvols != { }) {
      media = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = config.nori.inventory.backup.retention.coldMedia.localSnapshotPreserve;
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/mnt/media".subvolume = mediaSubvols;
        };
      };
    };
  };

  /*
    /mnt/media is a directory on the root filesystem, which is btrfs as
    well: without the IronWolf mount btrbk would receive the history onto
    the NVMe it is meant to relieve. RequiresMountsFor mounts the
    IronWolf snapshot subvolume first, or fails the unit.
  */
  assertions = [
    {
      assertion =
        ironwolf.attachedHost == config.networking.hostName
        && (config.fileSystems.${ironwolfSnapshots}.fsType or null) == "btrfs";
      message = "btrbk root target ${rootTarget} needs the attached IronWolf btrfs mounted at ${ironwolfSnapshots}.";
    }
  ];
  systemd.tmpfiles.rules = [ "d ${rootTarget} 0700 root root - -" ];

  # Alert via ntfy template in src/services/ntfy/nixos/notify.nix.
  systemd.services.btrbk-root.unitConfig = {
    OnFailure = [ "notify@btrbk-root.service" ];
    RequiresMountsFor = [ rootTarget ];
  };
  systemd.services.btrbk-family = lib.mkIf (familySubvols != { }) {
    unitConfig.OnFailure = [ "notify@btrbk-family.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/family" ];
  };
  systemd.services.btrbk-media = lib.mkIf (mediaSubvols != { }) {
    unitConfig.OnFailure = [ "notify@btrbk-media.service" ];
  };

  /*
    ── btrfs qgroup quota on @downloads ────────────────────────────
    Cap @downloads at 2540 GiB on the IronWolf (3726 GiB btrfs) to
    prevent the 100%-full metadata-exhaustion wedge pattern (see
    docs/runbooks/storage-full.md). At 100% btrfs can't even reclaim
    via subvolume delete because metadata writes need reserve — that's
    the actual recovery-hostile failure mode, not "disk full" itself.

    With the cap: qBit-as-writer hits ENOSPC on the @downloads quota
    well before the filesystem hits the metadata wall. Recovery path
    stays open (delete from @downloads to free; quota doesn't apply
    to the system pool's metadata budget).

    Headroom math (2026-09-26): 3053 GiB used, @downloads 2406 GiB
    referenced. The first btrbk-root send adds about 350 GiB (326 GiB
    data plus metadata), leaving about 998 GiB of non-download data.
    Disk-alert fires at 95% (3540 GiB), so a full @downloads may use
    3540 - 998 ≈ 2540 GiB: about 134 GiB above today's downloads. The
    previous 3300G cap no longer fit: it allowed ~890 GiB more
    downloads with only 670 GiB free.

    Tune via the 2540G literal below. Shrink it when other IronWolf
    data grows: the phase-2 root history (`retention.workstationRoot`)
    adds an estimated 110-160 GiB over six months.

    btrfs qgroup overhead: ~5% on metadata-heavy ops (modifying CoW
    ref counts on every write). Acceptable cost for the wedge guard
    on a non-CPU-bound media drive.

    Activation runs on every nixos-rebuild switch. `quota enable` is
    idempotent (no-op if already on). `qgroup limit` overwrites the
    existing limit cleanly. First-time enable triggers a rescan that
    may run for an hour on the multi-TiB filesystem; the limit takes
    effect after rescan completes.

    IMPORTANT — target path: /mnt/media itself is NOT a mountpoint
    (the downloads subvolume mounts directly under it). Targeting
    /mnt/media resolves to the root filesystem (SN750) and enables
    quotas there — wrong FS, expensive. Use /mnt/media/downloads, the
    real IronWolf mountpoint and the subvolume being capped. The family
    namespace is separate at /mnt/family and is not part of this quota.
  */
  system.activationScripts.btrfs-quota-media.text = ''
    if ${pkgs.util-linux}/bin/mountpoint -q /mnt/media/downloads; then
      ${pkgs.btrfs-progs}/bin/btrfs quota enable /mnt/media/downloads >/dev/null 2>&1 || true
      downloads_id=$(${pkgs.btrfs-progs}/bin/btrfs subvolume list /mnt/media/downloads \
        | ${pkgs.gawk}/bin/awk '$NF == "@downloads" { print $2 }')
      if [ -n "$downloads_id" ]; then
        ${pkgs.btrfs-progs}/bin/btrfs qgroup limit 2540G "0/$downloads_id" /mnt/media/downloads \
          || echo "WARNING: failed to set @downloads quota (rescan in progress?)"
      fi
    else
      echo "WARNING: /mnt/media/downloads is not mounted; skipping IronWolf quota setup"
    fi
  '';
}
