{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    # AMD Ryzen 5600X (Zen 3) tweaks + SSD profile. The sibling
    # common-cpu-amd-pstate (scaling-driver tuning) is not pulled
    # in — add when the tuning becomes a measured win.
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

  # Disk-backed swap as overflow tier behind zram (16 GiB compressed,
  # configured in modules/common/base.nix). zram absorbs most pressure
  # in-memory; this swapfile catches what zram can't compress further
  # — observed pre-freeze on 2026-06-06 (zram pegged at 16 GiB ceiling
  # for ~3 weeks before the UI froze under sustained memory pressure).
  #
  # Created out-of-band on @ subvol (not snapshotted by btrbk, which
  # only covers @home / @srv-share / @var-lib) via
  #   sudo btrfs filesystem mkswapfile --size 8G /swapfile
  # — handles NoCoW + no-compression + block preallocation in one step
  # (btrfs-progs 6.1+). Disko config should bake this into the install
  # path for future hosts.
  swapDevices = [ { device = "/swapfile"; } ];

  # --- IronWolf idle spindown -------------------------------------------
  # 4 TB Seagate IronWolf NAS HDD; ~5-7 W spinning at idle. Most media
  # access is bursty (jellyfin transcode start, immich library import,
  # btrbk hourly snapshot is metadata-only so doesn't require spin-up).
  # 20-min idle spindown trades ~50 kWh/year vs an ~8s spin-up latency
  # on first access. NAS-tier drives are rated for far more start/stop
  # cycles than consumer drives so the wear cost is acceptable.
  #
  # `-S 240` = 240 × 5s = 20 min spindown timer. Set on every boot
  # because the drive forgets it across power cycles.
  systemd.services.ironwolf-spindown = {
    description = "Set IronWolf 20min idle spindown timer";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.hdparm}/bin/hdparm -S 240 /dev/disk/by-id/ata-ST4000NE001-2MA101_WS24X543";
    };
  };

  # --- gpu (nvidia open, RTX 5060 Ti / Blackwell) -----------------------
  #
  # Driver-package fallback ladder per docs/TOPOLOGY.md § "GPU access":
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
