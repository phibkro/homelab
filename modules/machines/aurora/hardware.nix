{
  config,
  lib,
  modulesPath,
  ...
}:

/**
  ## aurora — Asus N552V · Intel Skylake-H i7-6700HQ · 12 GB DDR4 · NVIDIA GTX 950M

  Retired gaming laptop repurposed as the family-vault host. Dead
  battery, but otherwise solid: always-on AC, lid closed, runs headless.

   - **119 GB LiteOn SSD (`/dev/sda`)** — root + boot + `/nix`. btrfs
     subvols; no impermanence (immich-ml's CLIP/face weights are ~2 GB
     and worth keeping across reboots).
   - **932 GB Toshiba HDD (`/dev/sdb`)** — `/mnt/family/{photos,home-videos,
     projects,library,archive}`. The family vault.
   - **External Seagate OneTouch USB HDD** — `/mnt/backup/onetouch`,
     restic vault for both pi and workstation backups. SFTP-served via
     the chrooted `restic` user.

  Derived from `nixos-generate-config --no-filesystems` on the live
  ISO (2026-06-06). UEFI firmware. ~1 GB of the 12 GB is iGPU-pinned
  (Intel HD 530); ~11 GB usable for services.

  ## GPU posture

  NVIDIA GTX 950M (Maxwell) handles immich-ml CLIP + face recognition
  via the legacy_535 driver branch (`hardware.nvidia.package =
  config.boot.kernelPackages.nvidiaPackages.legacy_535`). Not enough
  VRAM for LLM inference — that stays on workstation's 5060 Ti.

  ## Why workhorse role

  Has GPU, has compute, hosts state. Classified workhorse — but it's a
  *minimal* workhorse. If a second compute-offload host ever appears,
  the rule-of-three signal is to extract a dedicated `compute` role
  then (see `modules/infra/hosts.nix § role`).
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
