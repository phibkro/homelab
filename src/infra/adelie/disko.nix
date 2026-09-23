_: {
  /*
    Samsung 990 Pro 1 TB system disk, pinned by model + serial. The installer
    currently sees it as nvme0n1, but /dev enumeration is not an identity.
    This is the sole disk this phase is permitted to partition.
  */
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_1TB_S7HDNU0L409926V";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
              extraArgs = [
                "-n"
                "BOOT"
              ];
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "nixos"
                "-f"
              ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@var-lib" = {
                  mountpoint = "/var/lib";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@snapshots" = {
                  mountpoint = "/.snapshots";
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
