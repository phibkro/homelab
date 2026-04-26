{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.disko.nixosModules.disko
    ../../modules/common
    ../../modules/lib/lan-route.nix
    ../../modules/services/samba.nix
    ../../modules/services/blocky.nix
    ../../modules/services/ollama.nix
    ../../modules/services/open-webui.nix
    ../../modules/services/jellyfin.nix
    ../../modules/services/ntfy.nix
    ../../modules/services/btrbk.nix
    ../../modules/services/beszel.nix
    ../../modules/services/gatus.nix
    ../../modules/services/authelia.nix
    ../../modules/services/caddy.nix
    ../../modules/services/backup-restic.nix
    ../../modules/services/arr-shared.nix
    ../../modules/services/qbittorrent.nix
    ../../modules/services/prowlarr.nix
    ../../modules/services/sonarr.nix
    ../../modules/services/radarr.nix
    ../../modules/services/bazarr.nix
    ../../modules/services/jellyseerr.nix
    ../../modules/desktop
    ./disko.nix
    ./disko-media.nix
    ./disko-onetouch.nix
    ./hardware.nix
  ];

  networking.hostName = "nori-station";
  networking.useDHCP = lib.mkDefault true;

  # Service modules (modules/services/*) get imported here in Phase 5,
  # picking the backup pattern (A/B/C) per service per docs/DESIGN.md
  # L210–289.
}
