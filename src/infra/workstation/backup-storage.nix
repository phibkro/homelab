{ config, lib, ... }:
let
  backup = config.nori.inventory.backup;
in
{
  /*
    Mount the existing filesystem only when a backup sender, restore drill, or
    Pi SFTP session touches it.  The automount gives an attached OneTouch a
    quiet idle state while preserving one authoritative path for every client.
    `nofail` keeps an unplugged portable backup disk outside the boot critical
    path; services that require it fail loudly through their mount assertions.
    No partitioning declaration: reconnecting populated archives must not
    format them.
  */
  fileSystems = lib.mkIf backup.enabled {
    ${backup.mountPoint} = {
      inherit (backup) device fsType;
      options = [
        "noatime"
        "nofail"
        "x-systemd.automount"
        "x-systemd.idle-timeout=15min"
        "x-systemd.device-timeout=30s"
      ];
    };
  };
}
