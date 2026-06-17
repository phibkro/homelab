_: {
  # Seagate OneTouch 5TB external HDD — restic backup target.
  # Physically relocated from workstation to aurora on 2026-06-11 (P13
  # of the aurora migration); same drive, same ext4 partition, same
  # mount path. Workstation reaches this repo over SFTP via the
  # `restic` chrooted user defined in modules/infra/backup/
  # restic-target.nix.
  #
  # By-id is stable across the host move — USB drives are identified
  # by their controller serial, not the host's USB port topology.
  # `usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0` (trailing -0:0 is
  # LUN 0) is the same string that worked on workstation.
  #
  # Re-running disko on this drive WIPES IT. The drive is already
  # formatted and populated — disko-time partitioning ONLY needs to
  # run on a brand-new replacement drive. Mount-time integration via
  # `fileSystems` flows from the existing GPT layout.

  disko.devices = {
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
                "x-systemd.automount"
                "x-systemd.idle-timeout=10min"
                "x-systemd.device-timeout=30s"
              ];
            };
          };
        };
      };
    };
  };
}
