_: {
  # ── nori.fs declarations ───────────────────────────────────────────
  # Named filesystem locations the IronWolf carries, paired with their
  # value tier. Service modules read `config.nori.fs.<n>.path`; backup
  # generators in modules/services/backup/ filter by `tier`. Single
  # source of truth for both the wire-format (disko) and the
  # service-facing interface — change one, the other is right here
  # next to it. See modules/effects/fs.nix for the schema.
  nori.fs = {
    downloads = {
      path = "/mnt/media/downloads";
      tier = "re-derivable";
    };
    photos = {
      path = "/mnt/media/photos";
      tier = "irreplaceable";
    };
    home-videos = {
      path = "/mnt/media/home-videos";
      tier = "irreplaceable";
    };
    projects = {
      path = "/mnt/media/projects";
      tier = "irreplaceable";
    };
    library = {
      path = "/mnt/media/library";
      tier = "irreplaceable";
    };
    archive = {
      path = "/mnt/media/archive";
      tier = "irreplaceable";
    };
  };

  # Declarative partition layout for workstation's IronWolf Pro media drive.
  # Phase 2 — applied AFTER the Phase 4 root install. Wipes the existing
  # exfat partition; preserve any irreplaceable data first.
  #
  #   nix run github:nix-community/disko/latest -- \
  #     --mode disko machines/workstation/disko-media.nix
  #
  # Layout (per docs/STORAGE.md § "Workstation media", plus @archive + @library added):
  #   single GPT partition spanning the disk, btrfs label
  #   `ironwolf-storage`, with seven subvolumes:
  #     @downloads    -> /mnt/media/downloads   (re-derivable: movies, shows,
  #                                              music; weekly snapshot only)
  #     @photos       -> /mnt/media/photos      (irreplaceable; daily + restic)
  #     @home-videos  -> /mnt/media/home-videos (irreplaceable; weekly + restic)
  #     @projects     -> /mnt/media/projects    (irreplaceable; weekly + restic)
  #     @library      -> /mnt/media/library     (curated media: books, comics;
  #                                              daily + restic; tier sits
  #                                              between @downloads (re-derivable)
  #                                              and @photos (irreplaceable))
  #     @archive      -> /mnt/media/archive     (cold; legacy machine backups)
  #     @snapshots    -> /mnt/media/.snapshots  (btrbk target on this FS)
  #
  # Mountpoints stay under /mnt/media/ — the label describes the
  # underlying drive, the mount path describes how it's served.
  #
  # All mounted subvolumes use compress=zstd:3,noatime. Disko emits the
  # corresponding fileSystems entries automatically when this module is
  # imported by a host's default.nix; do not also declare fileSystems
  # for these paths in hardware.nix.
  #
  # Disk identity is pinned by-id (model + serial) rather than /dev/sda
  # because /dev enumeration is unstable across kernel/BIOS changes —
  # the same lesson that bit workstation's NVMe enumeration between
  # Ubuntu and NixOS. by-id paths follow the hardware.

  disko.devices = {
    # The attribute name `media` is intentionally kept (not renamed to
    # something matching the new filesystem label) because disko derives
    # partition labels from this attribute name (`disk-media-root` ends
    # up as the on-disk PARTLABEL). Renaming it after the fact would
    # break the fileSystems entries disko emits — they'd point at a
    # PARTLABEL that doesn't exist on disk. The btrfs filesystem label
    # `ironwolf-storage` (below) is the human-friendly name.
    disk.media = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST4000NE001-2MA101_WS24X543";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "ironwolf-storage"
                "-f"
              ];

              subvolumes = {
                "@downloads" = {
                  mountpoint = "/mnt/media/downloads";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@photos" = {
                  mountpoint = "/mnt/media/photos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@home-videos" = {
                  mountpoint = "/mnt/media/home-videos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@projects" = {
                  mountpoint = "/mnt/media/projects";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@library" = {
                  # Curated media library — books (calibre-web) + comics
                  # (komga). Distinct from @downloads because these are
                  # uploaded/imported by hand, not auto-grabbed by an
                  # *arr; treat as projects-tier (daily snapshot, restic
                  # backed up). Distinct from @projects because the
                  # content is media (consumed) not work (produced).
                  mountpoint = "/mnt/media/library";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@archive" = {
                  # Archive — historical / cold data that doesn't belong
                  # in the active subvolumes. Backed up via restic per
                  # the same tier as @projects; weekly btrbk snapshots,
                  # keep 4. Initial population: legacy machine backups
                  # (asus-laptop, FIT-128GB, ubuntu-pc, nori-backup)
                  # migrated off the OneTouch when it became the restic
                  # target (Phase 5+; see git log around the OneTouch
                  # transition).
                  mountpoint = "/mnt/media/archive";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@restic-local" = {
                  # Always-mounted restic target, paired with the
                  # OneTouch via nori.backupTargets.ironwolf. Catches
                  # the failure mode where the OneTouch USB-bridge
                  # wedges (incident 2026-06-04): jobs writing here
                  # still succeed regardless of OneTouch state.
                  # Trade-off: same-drive backup of @photos/@projects/
                  # etc. doesn't survive an IronWolf drive failure —
                  # that's what the OneTouch (and future Hetzner)
                  # cover. The IronWolf target catches bit-rot,
                  # accidental delete, and OneTouch-glitch, which is
                  # the bulk of real recovery events.
                  # Mounted outside /mnt/media so the Samba shares
                  # (scoped to /mnt/media) can't accidentally expose
                  # the backup data.
                  mountpoint = "/mnt/backup-local";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@snapshots" = {
                  # Mounted so btrbk can write IronWolf-side snapshots
                  # there. Cross-filesystem snapshots aren't a thing in
                  # btrfs — root snapshots go to /.snapshots, IronWolf
                  # snapshots have to live on the IronWolf btrfs.
                  mountpoint = "/mnt/media/.snapshots";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
