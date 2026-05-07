{
  config,
  lib,
  pkgs,
  ...
}:

{
  # aarch64. Required: workstation builds Pi closures via aarch64
  # binfmt emulation (boot.binfmt.emulatedSystems = [ "aarch64-linux" ]
  # in modules/common/base.nix or similar — needs adding when station
  # starts building Pi closures regularly).
  nixpkgs.hostPlatform = "aarch64-linux";

  # Pi 4 boot, kernel, firmware, etc. all come from
  # nixos-hardware/raspberry-pi-4 (imported in ./default.nix).
  # The sd-image-aarch64 module handles partitioning + initial
  # filesystems (FIRMWARE = vfat boot, NIXOS_SD = ext4 root).
  # Auto-resize to fill the device on first boot is built in.

  # No swap on flash. zramSwap (compressed in-RAM) is the right
  # alternative if memory pressure shows up; do NOT enable physical
  # swap on USB flash — the wear gradient is steep.
  swapDevices = [ ];

  # Flash-friendly journald. Volatile = RAM-backed, no writes to
  # the FIT. SystemMaxUse=64M caps memory if the journal grows
  # under heavy log activity (which Pi shouldn't see anyway —
  # appliance role).
  services.journald.extraConfig = ''
    Storage=volatile
    SystemMaxUse=64M
  '';

  # Override aarch64-incompatible default. systemd-sysctl ships a
  # default `vm.mmap_rnd_bits = 33` (works on x86_64 with full 48-bit
  # VA), but aarch64 with the typical 39-bit VA layout maxes out
  # around 18-24. Without override, systemd-sysctl.service fails on
  # boot with `Couldn't write '33' to 'vm/mmap_rnd_bits': Invalid
  # argument`. Setting 18 is the conservative choice that works on
  # all aarch64 page-size + VA combinations.
  boot.kernel.sysctl."vm.mmap_rnd_bits" = lib.mkForce 18;
}
