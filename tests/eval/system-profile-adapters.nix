{ lib, ... }:

/**
  Pure placement proof for system-profile adapters.

  These modules used to arrive through the universal base bundle and then
  self-gate from host names or local declarations. The inventory must now be
  the only placement authority: removing a profile must remove its adapter.
*/

let
  inventory = import ../../inventory { inherit lib; };
  hostNames = lib.attrNames inventory.internal.hosts;

  hostsSelecting =
    modulePath:
    lib.filter (
      hostName:
      lib.elem (toString modulePath) (map toString (inventory.internal.systemModulesFor hostName))
    ) hostNames;

  actual = {
    vector = hostsSelecting ../../modules/infra/observability/vector.nix;
    btrbk = hostsSelecting ../../modules/infra/backup/btrbk.nix;
    restic = hostsSelecting ../../modules/infra/backup/restic.nix;
    restore-drill = hostsSelecting ../../modules/infra/backup/verify.nix;
    tailnet-appliance = hostsSelecting ../../modules/infra/tailnet-appliance.nix;
    entry-plane-role = hostsSelecting ../../modules/profiles/entry-plane.nix;
    research = hostsSelecting ../../modules/profiles/research.nix;
  };

  expected = {
    vector = [
      "aurora"
      "pi"
      "workstation"
    ];
    btrbk = [ "workstation" ];
    restic = [ "workstation" ];
    restore-drill = [ "workstation" ];
    tailnet-appliance = [ "pi" ];
    entry-plane-role = [ "pi" ];
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
