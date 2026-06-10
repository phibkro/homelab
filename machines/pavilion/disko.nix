_:

# Pavilion's disk layout — single 640 GB SATA rotational HDD,
# BIOS-firmware boot (no UEFI).
#
# ── Why btrfs subvolumes ───────────────────────────────────────────
# Impermanence (the "erase your darlings" pattern) requires either
# tmpfs root or a fast-rollback root. With only 3.6 GB RAM, tmpfs is
# too expensive; btrfs-rollback uses disk. Layout:
#
#   /dev/disk/by-id/ata-WDC_WD6400BPVT…
#   ├─ 1 MiB    BIOS boot partition (GRUB embed area)
#   ├─ 1 GiB    /boot           ext4  (kernels + initrd)
#   └─ rest     btrfs            subvolumes:
#                ├─ @root        →  /
#                ├─ @root-blank  →  template snapshotted onto @root at boot
#                ├─ @home        →  /home
#                ├─ @nix         →  /nix
#                └─ @persist     →  /persist
#
# The boot-time rollback service (../default.nix) snapshots
# @root-blank onto @root before the root mount, so every boot starts
# from the same clean state. /persist holds the declared survivors
# (ssh host keys, tailscale state, machine-id).
#
# ── Hardware identifier ────────────────────────────────────────────
# `device` is the stable by-id path captured from the live ISO. NEVER
# use /dev/sda — kernel enumeration is unstable across reboots.

{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD6400BPVT-60HXZT1_WD-WXH1A3190437";
      content = {
        type = "gpt";
        partitions = {
          # BIOS-boot partition — required for GRUB to embed its
          # stage 1.5 when booting from a GPT-formatted disk on a
          # BIOS-firmware machine. Tiny; not mounted at runtime.
          bios = {
            size = "1M";
            type = "EF02"; # BIOS boot partition GUID
          };

          # /boot — ext4. Kernels + initrd live here. Not on btrfs to
          # keep boot independent of any btrfs weirdness during early
          # boot rollback dance.
          boot = {
            size = "1G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/boot";
              mountOptions = [ "defaults" ];
            };
          };

          # The big btrfs partition with all the subvolumes.
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-L"
                "pavilion-root"
              ];
              subvolumes = {
                "/@root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                # Template snapshot — created empty after install,
                # then snapshotted onto @root on every boot by the
                # rollback service in default.nix. Never mounted.
                "/@root-blank" = { };
                "/@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                  ];
                };
                "/@nix" = {
                  mountpoint = "/nix";
                  # /nix is huge and read-mostly; aggressive
                  # compression to reduce the spinning-disk hit.
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                  ];
                };
                "/@persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd:1"
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

  # /persist must be mounted before impermanence binds its contents
  # over the freshly-rolled-back /. Disko sets neededForBoot via the
  # subvolume mountpoint, but the rollback service in default.nix
  # depends on /persist being available for the rollback target.
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
}
