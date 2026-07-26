{
  inputs,
  lib,
  ...
}:

/**
  Deployment control-plane projection test.

  Every build target comes from the unified host inventory. Known workload
  roots narrow affected-host plans; activation always places the entry plane
  after selected backends.
*/
let
  inventory = inputs.self.lib.noriInventory;
  deployment = inputs.self.lib.noriDeployment;
  inventoryHosts = lib.attrNames inventory.hosts;
  /*
    Every host is a NixOS host since the Intel Mac was retired; the flake no
    longer emits `homeConfigurations`. The inventory keeps its `kind`
    discriminator so re-adding a standalone home is an inventory entry rather
    than a schema change — but that branch is currently unexercised.
  */
  outputHosts = lib.sort builtins.lessThan (lib.attrNames inputs.self.nixosConfigurations);

  rootsCorrect =
    deployment.sourceRoots."modules/services/jellyfin" == [ "workstation" ]
    && deployment.sourceRoots."modules/services/arr" == [ "workstation" ]
    && deployment.sourceRoots."modules/services/filmder" == [ "aurora" ]
    && deployment.sourceRoots."modules/infra/networking/caddy" == [ "pi" ];

  targetsCorrect =
    deployment.targets.workstation.buildAttribute
    == "nixosConfigurations.workstation.config.system.build.toplevel";
in
if
  inventoryHosts == outputHosts
  && inventoryHosts == deployment.allHosts
  && inventory.deployment.targets == deployment.targets
  &&
    deployment.activationOrder == [
      "aurora"
      "pavilion"
      "workstation"
      "pi"
    ]
  && rootsCorrect
  && targetsCorrect
then
  "ok — deployment targets, change scopes, builds, and activation order derive from inventory"
else
  throw ''
    Deployment projection mismatch.
    Inventory hosts: ${builtins.toJSON inventoryHosts}
    Output hosts:    ${builtins.toJSON outputHosts}
    All targets:     ${builtins.toJSON deployment.allHosts}
    Activation:      ${builtins.toJSON deployment.activationOrder}
    Roots correct:   ${toString rootsCorrect}
    Targets correct: ${toString targetsCorrect}
  ''
