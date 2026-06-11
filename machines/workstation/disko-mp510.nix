_: {
  # ── nori.fs declarations ───────────────────────────────────────────
  # MP510 dual-role: workstation-side restic-local target
  # (/mnt/backup-local — replaces the IronWolf @restic-local subvol so
  # the IronWolf can be slimmed down post-P14) plus cold-replica
  # endpoints for aurora's /mnt/family/* via nightly btrfs send/receive
  # (/mnt/family-replica/*, declared in P15).
  #
  # `re-derivable` tier on the family-replica entries because the
  # source of truth lives on aurora — if MP510 fails, restoring is
  # re-running the btrfs receive timeline from aurora. They don't
  # land in any restic repo (aurora's restic covers the source data;
  # backing up a replica too would just double-spend backup budget).
  nori.fs = {
    # Temporary path until P14: the IronWolf `@restic-local` subvol
    # currently holds workstation's ~57 GiB of restic snapshots at
    # /mnt/backup-local. P14 migrates that data onto MP510 and swaps
    # the IronWolf subvol off; this subvol then becomes the canonical
    # /mnt/backup-local. For now it stays out of the way at
    # /mnt/mp510-backup-local with no consumers.
    mp510-backup-local = {
      path = "/mnt/mp510-backup-local";
      tier = "re-derivable";
    };
    family-replica-photos = {
      path = "/mnt/family-replica/photos";
      tier = "re-derivable";
    };
    family-replica-home-videos = {
      path = "/mnt/family-replica/home-videos";
      tier = "re-derivable";
    };
    family-replica-projects = {
      path = "/mnt/family-replica/projects";
      tier = "re-derivable";
    };
    family-replica-library = {
      path = "/mnt/family-replica/library";
      tier = "re-derivable";
    };
    family-replica-archive = {
      path = "/mnt/family-replica/archive";
      tier = "re-derivable";
    };
  };

  # Declarative partition layout for workstation's Corsair Force MP510
  # NVMe — formerly the Windows boot drive (ADR-0002 wiped 2026-06-11
  # after operator extracted the personal residue under /Users/piplu).
  #
  # Applied with:
  #
  #   nix run github:nix-community/disko/latest -- \
  #     --mode disko machines/workstation/disko-mp510.nix
  #
  # **One-shot wipe** — operator's responsibility to extract anything
  # off the prior NTFS partition before running disko. See
  # docs/superpowers/plans/2026-06-11-aurora-migration.md § P9.
  #
  # Single btrfs filesystem across the full disk (894 GB). Subvol map:
  #
  #   @backup-local              /mnt/mp510-backup-local (temp)
  #     P14 destination for workstation's restic-local target —
  #     replaces the IronWolf @restic-local subvol. Stays at the
  #     mp510-prefixed path until P14 migrates the existing ~57 GiB
  #     of restic snapshots off the IronWolf and swaps the mount.
  #
  #   @family-replica-photos     /mnt/family-replica/photos
  #   @family-replica-home-videos /mnt/family-replica/home-videos
  #   @family-replica-projects   /mnt/family-replica/projects
  #   @family-replica-library    /mnt/family-replica/library
  #   @family-replica-archive    /mnt/family-replica/archive
  #     btrfs receive endpoints for nightly aurora /mnt/family/* sync.
  #     Per-tier subvols so compress/snapshot policy stays per-tier;
  #     receive streams land as child subvols inside each mountpoint.
  #
  # All subvols use compress=zstd:3,noatime — same shape as the
  # IronWolf (disko-media.nix). Disk identity is pinned by-id so a
  # future kernel/BIOS reordering can't accidentally aim disko at
  # the SN750 root drive (same NVMe-enumeration trap that bit the
  # initial workstation install — see CLAUDE.md hard rule).

  disko.devices = {
    disk.mp510 = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Force_MP510_2031826300012953207B";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "mp510-backup"
                "-f"
              ];

              subvolumes = {
                "@backup-local" = {
                  mountpoint = "/mnt/mp510-backup-local";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@family-replica-photos" = {
                  mountpoint = "/mnt/family-replica/photos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@family-replica-home-videos" = {
                  mountpoint = "/mnt/family-replica/home-videos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@family-replica-projects" = {
                  mountpoint = "/mnt/family-replica/projects";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@family-replica-library" = {
                  mountpoint = "/mnt/family-replica/library";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@family-replica-archive" = {
                  mountpoint = "/mnt/family-replica/archive";
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
