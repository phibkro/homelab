{
  config,
  lib,
  modulesPath,
  ...
}:

/**
  ## aurora — Asus N552V · Intel Skylake-H i7-6700HQ · 12 GB DDR4 · NVIDIA GTX 950M

  Retired gaming laptop repurposed as an off-host backup appliance. Dead
  battery, but otherwise solid: always-on AC, lid closed, runs headless.

   - **119 GB LiteOn SSD (`/dev/sda`)** — root + boot + `/nix`.
   - **External Seagate OneTouch USB HDD** — `/mnt/backup`,
     restic vault for workstation backups. SFTP-served through
     the chrooted `restic` user.

  Derived from `nixos-generate-config --no-filesystems` on the live
  ISO (2026-06-06). UEFI firmware. ~1 GB of the 12 GB is iGPU-pinned
  (Intel HD 530); ~11 GB usable for services.

  ## GPU posture

  The NVIDIA GTX 950M remains available through the legacy_535 driver branch,
  but Aurora no longer runs Immich ML or the GPU exporter.

  ## Why workhorse role

  The existing `workhorse` role permits durable backup storage. Aurora's
  narrower purpose is explicit in its inventory workload: `restic-target`.
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
