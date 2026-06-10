{
  config,
  lib,
  modulesPath,
  ...
}:

# HP Pavilion g6 — hardware specifics.
#
# Derived from `nixos-generate-config --no-filesystems` on the live ISO
# (2026-06-05). CPU: AMD Athlon II P360 (mobile, Phenom II era, 2010);
# BIOS firmware (NOT UEFI — boot.loader uses GRUB, not systemd-boot,
# see ../default.nix); single 640 GB SATA rotational HDD; 3.6 GB RAM.
#
# The 3.6 GB ceiling drives the impermanence choice in default.nix —
# tmpfs-root would eat ~half of system RAM; btrfs-rollback keeps the
# "clean every boot" property without that cost. See default.nix.

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./disko.nix
  ];

  # Modules nixos-generate-config detected for this hardware. ohci_pci
  # + ehci_pci are legacy USB controllers (Phenom II chipset era);
  # ahci for SATA; rtsx_pci_sdmmc for the SD card slot.
  boot.initrd.availableKernelModules = [
    "ahci"
    "ohci_pci"
    "ehci_pci"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # AMD CPU detected. enableRedistributableFirmware is on via
  # modules/common, so this microcode flag activates correctly.
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # system.stateVersion is inherited from modules/common/base.nix.
  # When this host is first activated, set with
  #   lib.mkForce "26.05";
  # to pin its identity to the release it was installed against —
  # don't change after, even when the rest of the lab moves.
}
