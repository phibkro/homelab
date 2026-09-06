_: {
  /*
    MP510 retains historical workstation restic repositories and hosts
    SSD cache storage. No new backup jobs target it. Existing family-replica
    subvolumes remain mounted to preserve historical backup data. They are
    not evidence of a currently running cross-host replication service.
    Do not repartition or delete these subvolumes during this migration.
  */
  nori.fs = {
    /*
      Re-derivable fleet cache. Attic moved here when Aurora was reduced to
      the captive OneTouch restic target; cache availability must not depend
      on retired hardware.
    */
    cache = {
      path = "/mnt/backup-local/attic";
      tier = "re-derivable";
    };
    /*
      Workstation-side restic-local target — `nori.backupTargets.mp510`.
      Holds the ~57 GiB of workstation restic snapshots that used to
      live on the IronWolf `@restic-local` subvol; migrated in P14
      (2026-06-11) and the IronWolf @restic-local subvol dropped.
    */
    backup-local = {
      path = "/mnt/backup-local";
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

  /*
    Declarative partition layout for workstation's Corsair Force
    MP510 NVMe.

    Applied with:

      nix run github:nix-community/disko/latest -- \
        --mode disko infra/workstation/disko-mp510.nix

    **One-shot wipe** — operator's responsibility to extract anything
    off the prior NTFS partition before running disko. See
    docs/archive/plans/2026-06-11-aurora-migration.md § P9.

    Single btrfs filesystem across the full disk (894 GB). Subvol map:

      @backup-local              /mnt/backup-local
        workstation-side restic-local target —
        `nori.backupTargets.mp510` (drive-based name matching
        the `onetouch` convention). Replaced the IronWolf
        `@restic-local` subvol in P14 (2026-06-11); ~57 GiB
        of restic snapshots rsync'd over and the prior subvol
        dropped via `btrfs subvolume delete`.

      @family-replica-photos     /mnt/family-replica/photos
      @family-replica-home-videos /mnt/family-replica/home-videos
      @family-replica-projects   /mnt/family-replica/projects
      @family-replica-library    /mnt/family-replica/library
      @family-replica-archive    /mnt/family-replica/archive
        Historical btrfs receive endpoints; no active replication is declared.
        Per-tier subvols so compress/snapshot policy stays per-tier;
        receive streams land as child subvols inside each mountpoint.

    All subvols use compress=zstd:3,noatime — same shape as the
    IronWolf (disko-media.nix). Disk identity is pinned by-id so a
    future kernel/BIOS reordering can't accidentally aim disko at
    the SN750 root drive (same NVMe-enumeration trap that bit the
    initial workstation install — see CLAUDE.md hard rule).
  */

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
                  mountpoint = "/mnt/backup-local";
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
