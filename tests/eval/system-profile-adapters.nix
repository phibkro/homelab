{ lib, ... }:

/**
  Pure placement proof for system-profile adapters.

  These modules used to arrive through the universal base bundle and then
  self-gate from host names or local declarations. The inventory must now be
  the only placement authority: removing a profile must remove its adapter.
*/

let
  inventory = import ../../src/inventory { inherit lib; };
  # Ansible profiles still express logical workload placement, but they must
  # never be projected into NixOS system modules.
  hostNames = inventory.internal.nixosHostNames;

  hostsSelecting =
    modulePath:
    lib.filter (
      hostName:
      lib.elem (toString modulePath) (map toString (inventory.internal.systemModulesFor hostName))
    ) hostNames;
  mediaConfig =
    (lib.evalModules {
      specialArgs.pkgs = { };
      modules = [
        {
          options = {
            nori.inventory.currentWorkloads = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            nori.fs.downloads.path = lib.mkOption {
              type = lib.types.str;
            };
            nori.harden = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
            nori.backups = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
            services = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
            systemd = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
            users = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          };
          config = {
            nori.fs.downloads.path = "/tmp/downloads";
            nori.inventory.currentWorkloads = [ "sonarr" ];
          };
        }
        ../../src/profiles/media-acquisition/nixos.nix
      ];
    }).config;
  mediaActivationIsIsolated =
    mediaConfig.services.sonarr.enable
    && !(mediaConfig.services ? radarr)
    && !(mediaConfig.services ? qbittorrent)
    && !(mediaConfig.systemd.services ? recyclarr-sync);

  actual = {
    vector = hostsSelecting ../../src/services/vector/nixos.nix;
    btrbk = hostsSelecting ../../src/services/btrbk/nixos.nix;
    restic = hostsSelecting ../../src/services/restic-backup/nixos.nix;
    restore-drill = hostsSelecting ../../src/services/restore-drill/nixos.nix;
    research = hostsSelecting ../../src/profiles/research/nixos.nix;
  };

  expected = {
    vector = [
      "adelie"
      "workstation"
    ];
    btrbk = [ "workstation" ];
    restic = [
      "adelie"
      "workstation"
    ];
    restore-drill = [ "workstation" ];
    research = [ "workstation" ];
  };
in
if actual == expected && mediaActivationIsIsolated then
  "ok — system-profile adapters have explicit placement and media workload activation is isolated"
else
  throw ''
    System-profile adapter placement drifted.
    Expected: ${builtins.toJSON expected}
    Actual:   ${builtins.toJSON actual}
    Media activation isolated: ${toString mediaActivationIsIsolated}
  ''
