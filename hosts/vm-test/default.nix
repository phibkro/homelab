{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/common
    ./hardware.nix
  ];

  networking.hostName = "vm-test";
  networking.useDHCP = lib.mkDefault true;

  # No pillars enabled here. This host exists solely to validate the
  # install pipeline (flake eval, btrfs subvol mount, systemd-boot, ssh,
  # tailscale) before touching bare metal.
}
