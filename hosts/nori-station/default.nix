{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # Service groups — composable, non-exclusive aliases. See
  # modules/services/groups.nix for the group definitions and how a
  # new service slots in. Append/prepend additional `groups.<name>`
  # to the imports below as new concerns land.
  groups = import ../../modules/services/groups.nix;
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../modules/common
    ../../modules/lib/lan-route.nix
    ../../modules/lib/backup.nix
  ]
  ++ groups.networking # caddy + blocky
  ++ groups.auth # authelia
  ++ groups.observability # beszel + gatus + glance + ntfy
  ++ groups.backup # btrbk + restic
  ++ groups.ai # ollama + open-webui
  ++ groups.media # jellyfin + samba + calibre-web + komga
  ++ groups.arr # the *arr stack + qBittorrent + shared media group
  ++ groups.personal # radicale + syncthing
  ++ [
    ../../modules/desktop # Hyprland + greetd + audio + bars + apps + gaming

    ./disko.nix
    ./disko-media.nix
    ./disko-onetouch.nix
    ./windows-mount.nix
    ./hardware.nix
  ];

  networking.hostName = "nori-station";
  networking.useDHCP = lib.mkDefault true;
}
