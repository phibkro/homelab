{
  config,
  lib,
  modulesPath,
  ...
}:

/*
  Asus N552V — hardware specifics.

  Derived from `nixos-generate-config --no-filesystems` on the live
  ISO (2026-06-06). CPU: Intel Skylake-H (i7-6700HQ); UEFI firmware;
  12 GB RAM (~11 GB usable, ~1 GB for Intel HD 530 iGPU); discrete
  NVIDIA GM107M (GTX 950M, Maxwell); dual disk: 119 GB LiteOn SSD as
  /dev/sda (root + boot + /nix), 932 GB Toshiba HDD as /dev/sdb
  (currently unused — kept as future capacity).

  btrfs root with subvols on the SSD; no impermanence (immich-ml's
  CLIP/face weights are ~2 GB and worth keeping across reboots).
*/

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./disko.nix
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
  ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = "x86_64-linux";

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  /*
    NVIDIA GM107M (GTX 950M, Maxwell) — same device-node set as
    workstation's RTX 5060 Ti; consumed by services.immich.machine-
    learning.accelerationDevices via the schema in
    modules/infra/capabilities/gpu.nix. nvidia-modeset / -uvm-tools omitted as
    they're display / profiling-only and not needed for compute.
  */
  nori.gpu.nvidiaDevices = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-uvm"
  ];

  # system.stateVersion inherited from modules/machines/base/base.nix.
  # Pin with `lib.mkForce "26.05"` once activated.
}
