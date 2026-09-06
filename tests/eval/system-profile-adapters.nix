{ lib, ... }:

/**
  Pure placement proof for system-profile adapters.

  These modules used to arrive through the universal base bundle and then
  self-gate from host names or local declarations. The inventory must now be
  the only placement authority: removing a profile must remove its adapter.
*/

let
  inventory = import ../../inventory { inherit lib; };
  # Ansible profiles still express logical workload placement, but they must
  # never be projected into NixOS system modules.
  hostNames = inventory.internal.nixosHostNames;

  hostsSelecting =
    modulePath:
    lib.filter (
      hostName:
      lib.elem (toString modulePath) (map toString (inventory.internal.systemModulesFor hostName))
    ) hostNames;

  actual = {
    vector = hostsSelecting ../../services/vector/nixos.nix;
    btrbk = hostsSelecting ../../services/btrbk/nixos.nix;
    restic = hostsSelecting ../../services/restic-backup/nixos.nix;
    restore-drill = hostsSelecting ../../services/restore-drill/nixos.nix;
    research = hostsSelecting ../../profiles/research/nixos.nix;
  };

  expected = {
    vector = [ "workstation" ];
    btrbk = [ "workstation" ];
    restic = [ "workstation" ];
    restore-drill = [ "workstation" ];
    research = [ "workstation" ];
  };
in
if actual == expected then
  "ok — system-profile adapters have explicit, bounded placement"
else
  throw ''
    System-profile adapter placement drifted.
    Expected: ${builtins.toJSON expected}
    Actual:   ${builtins.toJSON actual}
  ''
