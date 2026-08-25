_: {
  /*
    ── nori.fs declarations ───────────────────────────────────────────
    Named filesystem locations the IronWolf carries, paired with their
    value tier. Service modules read `config.nori.fs.<n>.path`; backup
    generators in modules/infra/backup/ filter by `tier`. Single
    source of truth for both the wire-format (disko) and the
    service-facing interface — change one, the other is right here
    next to it. See modules/infra/storage/default.nix for the schema.
  */
  nori.fs = {
    downloads = {
      path = "/mnt/media/downloads";
      tier = "re-derivable";
    };
  };

  /*
    Declarative partition layout for workstation's IronWolf Pro media
    drive. The canonical family datasets now live on the Toshiba family
    vault imported from disko-family.nix; this module mounts only the
    re-derivable downloads tree and its snapshot area.

    The legacy family subvolumes remain declared below without mountpoints.
    Disko therefore retains/creates those physical subvolumes without
    mounting them, preserving their on-disk data while the canonical
    service-facing paths resolve under /mnt/family.

      nix run github:nix-community/disko/latest -- \
        --mode disko modules/machines/workstation/disko-media.nix

    All mounted subvolumes use compress=zstd:3,noatime. Disko emits the
    corresponding fileSystems entries automatically when this module is
    imported by a host's default.nix; do not also declare fileSystems
    for these paths in hardware.nix.

    Disk identity is pinned by-id (model + serial) rather than /dev/sda
    because /dev enumeration is unstable across kernel/BIOS changes —
    the same lesson that bit workstation's NVMe enumeration between
    Ubuntu and NixOS. by-id paths follow the hardware.
  */

  disko.devices = {
    /*
      The attribute name `media` is intentionally kept (not renamed to
      something matching the new filesystem label) because disko derives
      partition labels from this attribute name (`disk-media-root` ends
      up as the on-disk PARTLABEL). Renaming it after the fact would
      break the fileSystems entries disko emits — they'd point at a
      PARTLABEL that doesn't exist on disk. The btrfs filesystem label
      `ironwolf-storage` (below) is the human-friendly name.
    */
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
                "@downloads" = {
                  mountpoint = "/mnt/media/downloads";
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                # These legacy family subvolumes stay on the IronWolf but
                # are intentionally unmounted. The canonical copies live
                # on the Toshiba family vault at /mnt/family/*.
                "@photos" = { };
                "@home-videos" = { };
                "@projects" = { };
                "@library" = { };
                "@archive" = { };
                "@snapshots" = {
                  /*
                    Mounted so btrbk can write IronWolf-side snapshots
                    there. Cross-filesystem snapshots aren't a thing in
                    btrfs — root snapshots go to /.snapshots, IronWolf
                    snapshots have to live on the IronWolf btrfs.
                  */
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
