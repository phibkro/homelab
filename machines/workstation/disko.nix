_: {
  # ── nori.fs declarations ───────────────────────────────────────────
  # Named filesystem locations the SN750 root carries that service
  # modules and backup generators consume by name. /var/lib lives on
  # @var-lib but isn't in nori.fs — service StateDirectory paths are a
  # NixOS module convention, outside this Reader-effect's scope.
  # @nix and @ are infrastructure, not user-facing.
  nori.fs = {
    home = {
      path = "/home";
      tier = "user";
    };
    share = {
      path = "/srv/share";
      tier = "user";
    };
  };

  # Declarative partition layout for workstation's NVMe root.
  # Applied at install time:
  #   nix run github:nix-community/disko/latest -- \
  #     --mode disko hosts/workstation/disko.nix
  #
  # Layout (per docs/DESIGN.md L111–124):
  #   p1  ESP, 1 GiB, vfat, label BOOT
  #   p2  rest, btrfs, label nixos, six subvolumes:
  #     @            -> /
  #     @home        -> /home
  #     @nix         -> /nix
  #     @var-lib     -> /var/lib       (service state, separate snapshot cadence)
  #     @srv-share   -> /srv/share     (Samba-shared dumping ground)
  #     @snapshots   -> /.snapshots    (snapshot target)
  #
  # All btrfs subvolumes mount with compress=zstd:3,noatime. Disko emits
  # the corresponding fileSystems entries automatically; hosts/<host>/
  # hardware.nix must NOT also define them.
  #
  # Disk identity is pinned by-id (model + serial) — the WD Black SN750.
  # /dev enumeration is unstable: at install time this drive showed as
  # /dev/nvme0n1, but after a reboot the order flipped and the same
  # physical drive is /dev/nvme1n1 today (Windows MP510 took the n0
  # slot). Targeting /dev directly here would mean a future disko
  # invocation could wipe the wrong drive. by-id paths follow the
  # hardware.

  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WDS100T3X0C-00SJG0_204526810532";
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
                "@srv-share" = {
                  mountpoint = "/srv/share";
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
