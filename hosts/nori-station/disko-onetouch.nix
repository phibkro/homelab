{
  # Declarative partition layout for the Seagate One Touch 5TB external
  # HDD when it transitions from a Phase-1 rsync-to-exfat snapshot store
  # to a Phase-5 restic backup target.
  #
  # Phase ordering — apply ONLY after the Phase-A data move is complete
  # and verified (memories + projects + legacy machine backups all
  # migrated to IronWolf @photos / @projects / @archive). Re-running this
  # on a populated drive WIPES IT.
  #
  #   nix run github:nix-community/disko/latest -- \
  #     --mode disko hosts/nori-station/disko-onetouch.nix
  #
  # Layout choice — single GPT partition spanning the disk, ext4. Per
  # docs/DESIGN.md L143: restic encrypts client-side and is content-
  # addressable, so the underlying FS doesn't need btrfs's CoW or
  # snapshots; ext4 is the boring well-trodden choice for backup
  # targets. Keeping the FS family different from IronWolf's btrfs
  # also reduces the blast radius of a kernel btrfs regression.
  #
  # No subvolumes (ext4 doesn't have them). The backup-restic.nix
  # module points each backup job at /mnt/backup/<name>/, restic
  # creates its own internal directory layout.
  #
  # Mountpoint /mnt/backup — same path the future hosts/nori-pi/ will
  # use, so backup-restic.nix repository URLs are host-portable.
  #
  # Disk identity is by-id (model + serial). The OneTouch's by-id is
  # `usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0`. The trailing
  # `-0:0` is a USB target identifier (LUN 0). by-path would also work
  # for a single-USB-port setup but by-id is more stable across
  # USB-port reshuffling.

  disko.devices = {
    # Attribute name `onetouch-backup` — disko derives the on-disk
    # PARTLABEL from this; rename = repartition required.
    disk."onetouch-backup" = {
      type = "disk";
      device = "/dev/disk/by-id/usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              extraArgs = [
                "-L"
                "onetouch-backup"
              ];
              mountpoint = "/mnt/backup";
              mountOptions = [
                "defaults"
                "noatime"
                "nofail" # USB drive — don't block boot if disconnected
                # Lazy-mount: the FS is unmounted at idle, mounted on
                # first access. Restic touches /mnt/backup at 03:00 /
                # 03:30 / 04:00 daily and once weekly for the check
                # timer; the rest of the time the drive can spin down.
                # idle-timeout: how long after last access before
                # unmount. 10 min covers the 30-min daily backup batch
                # plus some slop.
                "x-systemd.automount"
                "x-systemd.idle-timeout=10min"
                "x-systemd.device-timeout=30s" # fail fast if drive yanked
              ];
            };
          };
        };
      };
    };
  };
}
