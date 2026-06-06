{ config, lib, modulesPath, ... }:

# Asus N552V — hardware specifics.
#
# ⚠ PLACEHOLDER ⚠ — fill in after first boot.
#
# Capture from a NixOS installer ISO booted on the actual hardware,
# then `nixos-generate-config --no-filesystems --root /mnt`:
#
#   * boot.initrd.availableKernelModules — Skylake-era laptop, likely
#     ahci + xhci_pci + nvme (if it has NVMe) or sd_mod + ahci (if
#     SATA SSD). nixos-generate-config detects.
#
#   * hardware.cpu.intel.updateMicrocode — Intel CPU; pin true.
#
#   * fileSystems."/", "/boot" — write disko.nix targeting the
#     real /dev/disk/by-id/<path>. Single SSD btrfs root + boot vfat
#     (UEFI). Skip impermanence — immich-ml caches CLIP + face models
#     (~2 GB), worth keeping across reboots.
#
#   * networking interface names — Asus N552V usually has Intel
#     I218-LM (e1000e) ethernet + Intel wifi (iwlwifi). Get the
#     actual names from `ip -br link` on the live ISO.

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    # ./disko.nix — written post-inventory; uncomment when ready
  ];

  boot.initrd.availableKernelModules = [ ]; # FILL IN
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
  ];
  boot.extraModulePackages = [ ];

  # Placeholder fileSystems so eval passes; replace with disko-derived
  # entries before deploy.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos"; # PLACEHOLDER
    fsType = "btrfs";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT"; # PLACEHOLDER
    fsType = "vfat";
  };

  nixpkgs.hostPlatform = "x86_64-linux";

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # system.stateVersion inherited from modules/common/base.nix.
  # Pin with `lib.mkForce "26.05"` (or whichever release the host is
  # first installed against) once activated.
}
