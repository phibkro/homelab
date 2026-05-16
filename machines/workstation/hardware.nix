{
  config,
  lib,
  inputs,
  ...
}:

{
  imports = [
    # AMD Ryzen 5600X (Zen 3) tweaks and general SSD profile.
    # common-cpu-amd-pstate intentionally omitted for first install — it
    # tweaks scaling driver options and isn't required for boot. Add
    # later once workstation is up and we want the tuning.
    inputs.nixos-hardware.nixosModules.common-cpu-amd
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
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Filesystems are emitted by ./disko.nix at install time. Do not declare
  # fileSystems here; disko's NixOS module produces them from the disko
  # config, and re-declaring would be a definition conflict.

  # No swap yet. If/when added: swapfile on the btrfs root with NoCoW
  # (chattr +C). Pattern goes in disko.nix, not here.
  swapDevices = [ ];

  # ── ZFS support (for the MP510 scratch pool) ──────────────────────
  # Adding zfs to supportedFilesystems pulls the in-tree-ish ZFS
  # kernel module (zfsutils-linux + spl) into the closure; without
  # this, mounting any ZFS dataset fails at boot. See
  # machines/workstation/disko-mp510.nix for the pool layout.
  boot.supportedFilesystems = [ "zfs" ];

  # ZFS requires a unique 8-char hex host ID — burned into the pool
  # at creation, checked on import. Without it, a pool moved between
  # hosts could be imported on two machines simultaneously and
  # corrupt itself. Derived once from /etc/machine-id (deterministic;
  # commits to git cleanly). Different per host.
  networking.hostId = "07fea3e9";

  # Don't auto-force-import on boot. If a pool import fails because
  # another host (or a previous boot) thinks it owns the pool, we
  # want to see the error and decide, not silently override.
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # --- gpu (nvidia open, RTX 5060 Ti / Blackwell) -----------------------
  #
  # Driver-package fallback ladder per docs/DESIGN.md L91–106:
  #   production  -> beta  -> latest  -> explicit mkDriver version
  # Known: 580.119.02 fails to build on kernel 6.19 (vm_area_struct API
  # change). 580.126.09 fixes it. If `production` resolves to .119 and
  # 6.19 is in use, fall back to `beta` or pin an older kernel.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true; # open kernel module (driver 575+ / Blackwell)
    modesetting.enable = true;
    nvidiaSettings = true; # nvidia-settings GUI for the desktop session
    powerManagement.enable = false;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Canonical GPU device list for services that opt in via
  # accelerationDevices / DeviceAllow. Default in modules/effects/gpu.nix
  # is empty; host explicitly enumerates what's present so Pi (no
  # GPU) doesn't get phantom device references.
  nori.gpu.nvidiaDevices = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
  ];

  # Build aarch64 closures locally for pi via binfmt emulation.
  # Cheaper than cross-compilation; closer to native build correctness.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
