{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # AMD Ryzen 5600X (Zen 3) tweaks and general SSD profile.
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  # --- boot --------------------------------------------------------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  # CPU microcode updates.
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  # --- filesystems -------------------------------------------------------
  #
  # Same layout as vm-test: one btrfs filesystem labelled "nixos" with four
  # subvolumes, plus an ESP labelled "BOOT" on nvme0n1p1. Identifying by
  # label instead of UUID keeps this stable across reinstalls.

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/.snapshots" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@snapshots" "compress=zstd:3" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # No swap yet. If/when added: swapfile on the btrfs root with NoCoW
  # (chattr +C) — not a ZRAM, not a partition. Size ~16 GB is plenty.
  swapDevices = [ ];

  # --- gpu (nvidia open, RTX 5060 Ti / Blackwell) -----------------------

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true;                  # open kernel module (driver 575+ / Blackwell)
    modesetting.enable = true;
    nvidiaSettings = false;        # headless — no nvidia-settings GUI
    powerManagement.enable = false;
    # The driver package choice depends on what nixpkgs-unstable ships at
    # the time of install. Verify during first build: the driver must be
    # 575 or newer for Blackwell. If `production` is older, try `beta` or
    # `latest`, or pin an explicit version.
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
