{ config, lib, ... }:
let
  backup = config.nori.inventory.backup;
in
{
  # Mount the existing filesystem only after the operator verifies the drive.
  # No partitioning declaration: reconnecting populated archives must not format them.
  fileSystems = lib.mkIf backup.enabled {
    ${backup.mountPoint} = {
      inherit (backup) device fsType;
      options = [
        "noatime"
        "nofail"
        "x-systemd.device-timeout=30s"
      ];
    };
  };
}
