{
  # Declarative partition layout for nori-station's IronWolf Pro media drive.
  # Phase 2 — applied AFTER the Phase 4 root install. Wipes the existing
  # exfat partition; preserve any irreplaceable data first.
  #
  #   nix run github:nix-community/disko/latest -- \
  #     --mode disko hosts/nori-station/disko-media.nix
  #
  # Layout (per docs/DESIGN.md L130–138):
  #   single GPT partition spanning the disk, btrfs label
  #   `ironwolf-storage`, with five subvolumes:
  #     @streaming    -> /mnt/media/streaming
  #     @photos       -> /mnt/media/photos
  #     @home-videos  -> /mnt/media/home-videos
  #     @projects     -> /mnt/media/projects
  #     @snapshots    -> (unmounted; btrbk uses the subvolume directly)
  #
  # Mountpoints stay under /mnt/media/ — the label describes the
  # underlying drive, the mount path describes how it's served.
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
    # The attribute name `media` is intentionally kept (not renamed to
    # something matching the new filesystem label) because disko derives
    # partition labels from this attribute name (`disk-media-root` ends
    # up as the on-disk PARTLABEL). Renaming it after the fact would
    # break the fileSystems entries disko emits — they'd point at a
    # PARTLABEL that doesn't exist on disk. The btrfs filesystem label
    # `ironwolf-storage` (below) is the human-friendly name.
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
              extraArgs = [
                "-L"
                "ironwolf-storage"
                "-f"
              ];

              subvolumes = {
                "@streaming" = {
                  mountpoint = "/mnt/media/streaming";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@photos" = {
                  mountpoint = "/mnt/media/photos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@home-videos" = {
                  mountpoint = "/mnt/media/home-videos";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@projects" = {
                  mountpoint = "/mnt/media/projects";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "@snapshots" = {
                  # Mounted so btrbk can write IronWolf-side snapshots
                  # there. Cross-filesystem snapshots aren't a thing in
                  # btrfs — root snapshots go to /.snapshots, IronWolf
                  # snapshots have to live on the IronWolf btrfs.
                  mountpoint = "/mnt/media/.snapshots";
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
