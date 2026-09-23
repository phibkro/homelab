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
  outputHosts = lib.sort builtins.lessThan (lib.attrNames inputs.self.nixosConfigurations);
  nixosInventoryHosts = lib.attrNames (
    lib.filterAttrs (_: host: host.kind == "nixos") inventory.hosts
  );
  rawHosts = import ../../src/inventory/hosts.nix;
  compiler = import ../../src/inventory;
  ansibleHostCannotCarryNixModules =
    let
      invalidHosts = rawHosts // {
        pi = rawHosts.pi // {
          systemModule = ../../src/infra/workstation;
        };
      };
      evaluated = builtins.tryEval (
        builtins.deepSeq
          (compiler {
            inherit lib;
            hosts = invalidHosts;
          }).public
          true
      );
    in
    !evaluated.success;
  ansibleHostCannotProjectNixModules =
    let
      evaluated = builtins.tryEval (
        builtins.deepSeq ((compiler { inherit lib; }).internal.systemModulesFor "pi") true
      );
    in
    !evaluated.success;

  rootsCorrect =
    deployment.sourceRoots."src/services/attic" == [ "adelie" ]
    &&
      deployment.sourceRoots."src/services/attic-publisher" == [
        "adelie"
        "workstation"
      ]
    && deployment.sourceRoots."src/services/music-ingest" == [ "workstation" ]
    && deployment.sourceRoots."src/services/jellyfin" == [ "workstation" ]
    && deployment.sourceRoots."src/profiles/media-acquisition" == [ "workstation" ]
    && deployment.sourceRoots."src/services/grafana" == [ "adelie" ]
    && deployment.sourceRoots."src/services/restic-target" == [ "workstation" ]
    && deployment.sourceRoots."src/services/caddy/manifest.nix" == [ "pi" ]
    &&
      deployment.sourceRoots."src/services/beszel/manifests/agent.nix" == [
        "adelie"
        "pi"
        "workstation"
      ]
    &&
      deployment.sourceRoots."src/services/ntfy/manifests/notify.nix" == [
        "adelie"
        "pi"
        "workstation"
      ]
    && deployment.machineRoots."src/services/caddy/ansible" == [ "pi" ]
    && deployment.machineRoots."src/services/glance/ansible" == [ "pi" ]
    && deployment.machineRoots."src/services/beszel/ansible/agent" == [ "pi" ]
    && deployment.machineRoots."src/services/beszel/ansible/hub" == [ "pi" ]
    && deployment.machineRoots."src/services/ntfy/ansible" == [ "pi" ]
    && deployment.machineRoots."src/services/bazarr" == [ "workstation" ]
    && deployment.machineRoots."src/services/jellyseerr" == [ "workstation" ]
    && deployment.machineRoots."src/services/lidarr" == [ "workstation" ]
    && deployment.machineRoots."src/services/prowlarr" == [ "workstation" ]
    && deployment.machineRoots."src/services/qbittorrent" == [ "workstation" ]
    && deployment.machineRoots."src/services/radarr" == [ "workstation" ]
    && deployment.machineRoots."src/services/recyclarr" == [ "workstation" ]
    && deployment.machineRoots."src/services/sonarr" == [ "workstation" ]
    && deployment.machineRoots."src/infra/common/ansible" == [ "pi" ]
    && deployment.machineRoots."src/infra/adelie" == [ "adelie" ]
    && deployment.machineRoots."src/infra/pi" == [ "pi" ]
    && deployment.machineRoots."src/infra/workstation" == [ "workstation" ];

  targetsCorrect =
    deployment.targets.adelie == {
      kind = "nixos";
      profiles = [
        "base"
        "graphical-desktop"
        "log-forwarder"
        "remote-backup-source"
        "observability-agent"
      ];
      workloads = inventory.hosts.adelie.workloads;
      buildAttribute = "nixosConfigurations.adelie.config.system.build.toplevel";
      planCommand = null;
      applyCommand = null;
      verifyCommand = null;
    }
    &&
      deployment.targets.workstation.buildAttribute
      == "nixosConfigurations.workstation.config.system.build.toplevel"
    &&
      deployment.targets.pi == {
        kind = "ansible";
        profiles = [
          "base"
          "entry-plane"
          "log-forwarder"
        ];
        workloads = inventory.hosts.pi.workloads;
        buildAttribute = null;
        planCommand = "just pi::plan";
        applyCommand = "just pi::deploy";
        verifyCommand = "just pi::check";
      };
in
if
  outputHosts == nixosInventoryHosts
  &&
    outputHosts == [
      "adelie"
      "workstation"
    ]
  && !(inputs.self.nixosConfigurations ? pi)
  && inventoryHosts == deployment.allHosts
  && deployment.buildOrder == outputHosts
  && inventory.deployment.targets == deployment.targets
  &&
    deployment.activationOrder == [
      "adelie"
      "workstation"
      "pi"
    ]
  && rootsCorrect
  && targetsCorrect
  && ansibleHostCannotCarryNixModules
  && ansibleHostCannotProjectNixModules
then
  "ok — deployment ownership, change scopes, builds, and activation order derive from inventory"
else
  throw ''
    Deployment projection mismatch.
    Inventory hosts: ${builtins.toJSON inventoryHosts}
    Output hosts:    ${builtins.toJSON outputHosts}
    All targets:     ${builtins.toJSON deployment.allHosts}
    Activation:      ${builtins.toJSON deployment.activationOrder}
    Roots correct:   ${toString rootsCorrect}
    Targets correct: ${toString targetsCorrect}
    Backend split:   ${toString ansibleHostCannotCarryNixModules}
    Module boundary: ${toString ansibleHostCannotProjectNixModules}
  ''
