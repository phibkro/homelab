{
  lib,
  inputs,
  ...
}:

{
  # nori-station is a server + a desktop. Each `modules/<concern>`
  # import is one role this machine plays; the host is the sum of
  # its concerns plus its physical hardware.
  imports = [
    inputs.disko.nixosModules.disko

    ../../modules/common # base + users + sops + tailscale + lib options
    ../../modules/server # every server module (HTTP, *arr, backup, …)
    ../../modules/desktop # Hyprland + greetd + audio + bars + apps + gaming

    ./hardware.nix
    ./disko.nix
    ./disko-media.nix
    ./disko-onetouch.nix
    ./windows-mount.nix
  ];

  networking.hostName = "nori-station";
  networking.useDHCP = lib.mkDefault true;
}
