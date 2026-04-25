{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    inputs.disko.nixosModules.disko
    ../../modules/common
    ./disko.nix
    ./hardware.nix
  ];

  networking.hostName = "nori-station";
  networking.useDHCP = lib.mkDefault true;

  # Service modules (modules/services/*) get imported here in Phase 5,
  # picking the backup pattern (A/B/C) per service per docs/DESIGN.md
  # L210–289.
}
