{
  lib,
  modulesPath,
  inputs,
  ...
}:

/**
  Raspberry Pi 4 realization for the always-on entry-plane profile.

  Role policy lives in `modules/profiles/entry-plane.nix`; this node file owns
  only board/image composition and the cached-kernel compatibility deviation.
*/

{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4

    # Provides `system.build.sdImage` for cross-built flashable images.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ./hardware.nix
  ];

  networking.useDHCP = lib.mkDefault true;

  /*
    Allows the post-build shrink step to skip initrd modules the upstream
    Raspberry Pi hardware module requests but the kernel does not provide
    (notably `dw-hdmi`), so a real boot-module regression is silent here.

    This was adopted to accept a prebuilt `linux-rpi` that omitted those
    modules. That kernel is now compiled from source, so the omission may no
    longer occur; dropping this line and letting the CI pi-build job fail
    loudly is the check that has not been run yet.
  */
  boot.initrd.allowMissingModules = true;
}
