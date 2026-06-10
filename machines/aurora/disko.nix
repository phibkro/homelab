_:

# Aurora disk layout — 119 GB LiteOn SSD only. The 932 GB Toshiba HDD
# (sdb) is intentionally left alone for now; future capacity for an
# immich originals cache or similar. To use it later, declare a
# second disk entry here and a `nori.fs.<X>` mountpoint.
#
# Single SSD layout, UEFI/systemd-boot:
#
#   /dev/disk/by-id/ata-LITEON_CV1-8B128_0026431011E9
#   ├─ 512 MiB  /boot         vfat   (ESP)
#   └─ rest     btrfs          subvolumes:
#                ├─ @root      → /
#                ├─ @home      → /home
#                └─ @nix       → /nix
#
# No impermanence on this host — see header in default.nix. zstd:1
# compression everywhere except /nix which gets zstd:3 (read-mostly,
# heavy benefit from better compression).

{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/ata-LITEON_CV1-8B128_0026431011E9";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "512M";
            type = "EF00"; # EFI system partition GUID
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-L"
                "aurora-root"
              ];
              subvolumes = {
                "/@root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@nix" = {
                  mountpoint = "/nix";
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
