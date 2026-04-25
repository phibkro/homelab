{
  # Declarative partition layout for nori-station's IronWolf Pro media drive.
  # Phase 2 — applied AFTER the Phase 4 root install. Wipes the existing
  # exfat partition; preserve any irreplaceable data first.
  #
  #   nix run github:nix-community/disko/latest -- \
  #     --mode disko hosts/nori-station/disko-media.nix
  #
  # Layout (per docs/DESIGN.md L130–138):
  #   single GPT partition spanning the disk, btrfs label `media`, with:
  #     @streaming    -> /mnt/media/streaming
  #     @photos       -> /mnt/media/photos
  #     @home-videos  -> /mnt/media/home-videos
  #     @projects     -> /mnt/media/projects
  #     @snapshots    -> (unmounted; btrbk uses the subvolume directly)
  #
  # All mounted subvolumes use compress=zstd:3,noatime. Disko emits the
  # corresponding fileSystems entries automatically when this module is
  # imported by a host's default.nix; do not also declare fileSystems
  # for these paths in hardware.nix.
  #
  # Disk identity is pinned by-id (model + serial) rather than /dev/sda
  # because /dev enumeration is unstable across kernel/BIOS changes —
  # the same lesson that bit nori-station's NVMe enumeration between
  # Ubuntu and NixOS. by-id paths follow the hardware.

  disko.devices = {
    disk.media = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST4000NE001-2MA101_WS24X543";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-L" "media" "-f" ];

              subvolumes = {
                "@streaming" = {
                  mountpoint = "/mnt/media/streaming";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@photos" = {
                  mountpoint = "/mnt/media/photos";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@home-videos" = {
                  mountpoint = "/mnt/media/home-videos";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@projects" = {
                  mountpoint = "/mnt/media/projects";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@snapshots" = {
                  # No mountpoint — btrbk operates on the subvolume directly.
                };
              };
            };
          };
        };
      };
    };
  };
}
