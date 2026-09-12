/*
  External, migratable storage inventory.

  NVMe system disks stay in their owning host's disko module: their layout is
  a host-local boot concern. These two disks are portable fleet assets, so
  their physical identity, filesystem contract, role, and current attachment
  belong here. Consumers derive by-id paths from this registry; moving a disk
  still requires an explicit host realization change and direct hardware
  verification before any activation.
*/
{
  "ironwolf-pro" = {
    role = "cold-primary";
    attachedHost = "workstation";
    mountPoint = "/mnt/media";
    identity = {
      byId = "/dev/disk/by-id/ata-ST4000NE001-2MA101_WS24X543";
      model = "ST4000NE001-2MA101";
      serial = "WS24X543";
      capacityBytes = 4000787030016;
      transport = "sata";
    };
    filesystem = {
      device = "/dev/disk/by-id/ata-ST4000NE001-2MA101_WS24X543-part1";
      type = "btrfs";
      label = "ironwolf-storage";
    };
  };

  "one-touch" = {
    role = "backup";
    attachedHost = "workstation";
    mountPoint = "/mnt/backup";
    identity = {
      byId = "/dev/disk/by-id/usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0";
      model = "One Touch HDD";
      serial = "00000000NABNR6G2";
      capacityBytes = 5000981078016;
      transport = "usb";
    };
    filesystem = {
      device = "/dev/disk/by-id/usb-Seagate_One_Touch_HDD_00000000NABNR6G2-0:0-part1";
      type = "ext4";
      label = "onetouch-backup";
    };
  };
}
