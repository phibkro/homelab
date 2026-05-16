_: {
  # ── MP510 NVMe — ZFS `fast` pool ─────────────────────────────────
  # The drive previously held a Windows 10/11 install (NTFS C: + ESP +
  # MSR + WinRE). All irreplaceable data was extracted to
  # /mnt/backup/windows-piplu/ during earlier work and verified against
  # Immich (Saved Pictures) in this session. Repurposing the 894 GiB
  # NVMe as a ZFS pool for two roles:
  #
  #   * fast/vm     — block storage for microvm.nix VMs (queued
  #                    stabilization phase 5). zvols created per VM
  #                    beneath this dataset.
  #   * fast/restic — local fast-restore tier alongside /mnt/backup
  #                    (OneTouch). Bigger restic repos (immich,
  #                    vaultwarden) copy into here for hot recovery;
  #                    OneTouch stays the canonical cold tier with
  #                    longer retention.
  #
  # ── Pool name ───────────────────────────────────────────────────
  # `fast` names the tier (NVMe vs IronWolf HDD vs OneTouch USB).
  # Pairs with the existing function-named mountpoints `/mnt/media`
  # (bulk tier) and `/mnt/backup` (cold tier). Not `scratch` despite
  # the HPC convention — scratch implies auto-purged ephemeral
  # workspace, and both datasets here persist for the lifetime of
  # what owns them.
  #
  # ── Why ZFS here (not btrfs like the rest of the stack) ─────────
  # ZFS gives per-dataset `reservation` + `quota` properties — a
  # dataset can be guaranteed N bytes that no other dataset can
  # consume. Useful when two datasets share a pool and one (vm) could
  # otherwise starve the other (restic). btrfs qgroups give the quota
  # half but not the reservation half. The IronWolf wedge pattern
  # (100%-full metadata-exhaustion) is also handled more gracefully
  # by ZFS — more aggressive per-dataset metadata reserve.
  #
  # This drive isn't where qBit downloads (the IronWolf still hosts
  # @downloads); the ZFS-vs-btrfs choice here is about isolating the
  # VM workload from the fast-restore restic tier and getting ZFS
  # into the stack ahead of the microvm.nix work.
  #
  # ── Apply (DESTRUCTIVE — wipes Windows on nvme0n1) ──────────────
  #   sudo nix run github:nix-community/disko/latest -- \
  #     --mode destroy,format,mount machines/workstation/disko-mp510.nix
  #
  # Pre-flight: ensure /mnt/windows-ro is unmounted (windows-mount.nix
  # was removed from the workstation imports in the commit that lands
  # this file). Re-flight: `zpool status fast` should show ONLINE
  # with the single nvme0n1 vdev.
  #
  # ── by-id pinning ───────────────────────────────────────────────
  # /dev/nvme0n1 enumeration is unstable across reboots (CLAUDE.md
  # hard rule — the same drive was the NixOS root at install time);
  # by-id (model + serial) is the only safe identifier. Verified
  # 2026-05-16 against `lsblk -o NAME,MODEL` (Force MP510, 894.3 G).

  disko.devices = {
    disk.fast = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Force_MP510_2031826300012953207B";
      content = {
        type = "gpt";
        partitions.zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "fast";
          };
        };
      };
    };

    zpool.fast = {
      type = "zpool";
      # Single vdev — no mirror / raidz. One drive in the pool.
      # Resilience here is "re-derivable" (microvm disks rebuilt from
      # declarative config; fast/restic is a copy of the OneTouch
      # repo). No redundancy needed at the FS layer.
      mode = "";
      rootFsOptions = {
        # zstd default level. Compression on for the same reason
        # btrfs gets compress=zstd:3 elsewhere — VM disks have high
        # redundancy, restic chunks are already compressed so this
        # has near-zero downside there.
        compression = "zstd";
        # No access-time updates — every read becoming a write costs
        # write amplification on the NVMe + makes snapshot bookkeeping
        # noisier. Same as the btrfs `noatime` everywhere else.
        atime = "off";
        # Store xattrs in inodes (sa) instead of separate hidden files
        # — faster lookups, smaller on-disk footprint, required for
        # POSIX ACLs to be efficient.
        xattr = "sa";
        acltype = "posixacl";
        # Don't mount the root dataset itself; each child dataset has
        # its own mountpoint. Prevents accidental "wrote to the pool
        # root" mistakes.
        mountpoint = "none";
      };
      options = {
        # 4K physical sector size on modern NVMe. ashift=12 = 2^12 =
        # 4096 byte alignment. Set at pool create; can't change later.
        ashift = "12";
        # Pool stays imported across reboots via the systemd zfs-mount
        # service. Default cachefile behavior works here.
      };
      datasets = {
        vm = {
          type = "zfs_fs";
          mountpoint = "/mnt/fast/vm";
          # Dataset-level options. recordsize stays default (128K) —
          # individual zvols underneath will set their own block size
          # appropriate to the VM workload (volblocksize, typically
          # 16K for ext4-formatted zvols, 64K for btrfs-on-zvol).
        };
        restic = {
          type = "zfs_fs";
          mountpoint = "/mnt/fast/restic";
          # restic stores ~5 MiB chunks; default 128K recordsize
          # produces tolerable IO patterns. If/when this becomes the
          # bottleneck, bump to 1M.
        };
      };
    };
  };
}
