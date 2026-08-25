_: {
  /*
    Seagate OneTouch 5TB external HDD — local restic backup target.
    The physical drive is mounted on workstation at /mnt/backup; the
    existing ext4 partition and repository names are preserved so the
    moved drive is reused without reinitialization.

    By-id is stable across host moves — USB drives are identified by
    their controller serial, not the host's USB port topology.
    `usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0` (trailing -0:0 is
    LUN 0) is the existing identity for this drive.

    Re-running disko on this drive WIPES IT. The drive is already
    formatted and populated — disko-time partitioning ONLY needs to
    run on a brand-new replacement drive. Mount-time integration via
    `fileSystems` flows from the existing GPT layout.
  */

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
