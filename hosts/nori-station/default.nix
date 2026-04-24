{ config, lib, pkgs, ... }:

{
  imports = [
    ../common.nix
    ./hardware.nix
  ];

  networking.hostName = "nori-station";
  networking.useDHCP = lib.mkDefault true;

  # Pillars (Phase 5): currently empty. When modules/ai, modules/homelab,
  # and modules/public gain real content, they import here.
  #
  #   ../../modules/ai
  #   ../../modules/homelab
  #   ../../modules/public
}
