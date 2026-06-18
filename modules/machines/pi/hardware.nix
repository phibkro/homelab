{
  lib,
  ...
}:

/**
  ## pi — Raspberry Pi 4 (8 GiB) · aarch64 · USB-boot from Samsung FIT 128 GB

  **Anti-write storage posture.** SD-card / flash wear is the #1 Pi failure
  mode; this host's filesystem layer is configured to minimize writes:

   - `swapDevices = [ ]` — no physical swap. zramSwap (RAM-backed compressed)
     is the right alternative if memory pressure ever shows up.
   - `services.journald.extraConfig` — `Storage=volatile` (RAM-backed
     journal) + `SystemMaxUse=64M` cap.
   - `boot.kernel.sysctl."vm.mmap_rnd_bits" = 18` — aarch64 fixup (default
     33 from x86_64 systemd fails on aarch64's 39-bit VA).

  **Restic-as-target deferred:** Pi can host the workstation restic repo
  only when a real disk replaces the FIT — the anti-write posture rules
  out daily restic to flash.

  **NVMe enumeration warning.** Disko configs target `/dev/disk/by-id/...`
  paths because NVMe enumeration is unstable across reboots. Pi itself
  doesn't have NVMe today, but the convention is universal in this repo;
  see `.claude/skills/gotcha-nvme-enumeration/`.

  ## Build path

  Pi closures build on workstation via aarch64 binfmt emulation
  (`boot.binfmt.emulatedSystems` in `modules/machines/workstation/hardware.nix`);
  the sd-image-aarch64 module handles partitioning. Flashed once, then
  rebuilt in-place via `nh os switch` over tailnet.
*/

{
  # aarch64. Workstation builds Pi closures via aarch64 binfmt
  # emulation (boot.binfmt.emulatedSystems in workstation/hardware.nix).
  nixpkgs.hostPlatform = "aarch64-linux";

  /*
    Pi 4 boot, kernel, firmware, etc. all come from
    nixos-hardware/raspberry-pi-4 (imported in ./default.nix).
    The sd-image-aarch64 module handles partitioning + initial
    filesystems (FIRMWARE = vfat boot, NIXOS_SD = ext4 root).
    Auto-resize to fill the device on first boot is built in.
  */

  /*
    No swap on flash. zramSwap (compressed in-RAM) is the right
    alternative if memory pressure shows up; do NOT enable physical
    swap on USB flash — the wear gradient is steep.
  */
  swapDevices = [ ];

  /*
    Flash-friendly journald. Volatile = RAM-backed, no writes to
    the FIT. SystemMaxUse=64M caps memory if the journal grows
    under heavy log activity (which Pi shouldn't see anyway —
    appliance role).
  */
  services.journald.extraConfig = ''
    Storage=volatile
    SystemMaxUse=64M
  '';

  /*
    Override aarch64-incompatible default. systemd-sysctl ships a
    default `vm.mmap_rnd_bits = 33` (works on x86_64 with full 48-bit
    VA), but aarch64 with the typical 39-bit VA layout maxes out
    around 18-24. Without override, systemd-sysctl.service fails on
    boot with `Couldn't write '33' to 'vm/mmap_rnd_bits': Invalid
    argument`. Setting 18 is the conservative choice that works on
    all aarch64 page-size + VA combinations.
  */
  boot.kernel.sysctl."vm.mmap_rnd_bits" = lib.mkForce 18;
}
