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
    Garnix's cached `linux-rpi` can omit modules requested by the upstream
    Raspberry Pi hardware module (notably `dw-hdmi`). Allow the post-build
    shrink step to skip those absent modules instead of forcing an hour-long
    emulated kernel rebuild. A real boot-module regression can therefore be
    silent; the trade-off is specific to this appliance image path.
  */
  boot.initrd.allowMissingModules = true;
}
