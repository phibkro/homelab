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
  rawHosts = import ../../inventory/hosts.nix;
  compiler = import ../../inventory;
  ansibleHostCannotCarryNixModules =
    let
      invalidHosts = rawHosts // {
        pi = rawHosts.pi // {
          systemModule = ../../infra/workstation;
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
    deployment.sourceRoots."services/attic" == [ "adelie" ]
    &&
      deployment.sourceRoots."services/attic-publisher" == [
        "adelie"
        "workstation"
      ]
    && deployment.sourceRoots."services/music-ingest" == [ "workstation" ]
    && deployment.sourceRoots."services/jellyfin" == [ "workstation" ]
    && deployment.sourceRoots."profiles/media-acquisition" == [ "workstation" ]
    && deployment.sourceRoots."services/grafana" == [ "adelie" ]
    && deployment.sourceRoots."services/restic-target" == [ "workstation" ]
    && deployment.sourceRoots."services/caddy/manifest.nix" == [ "pi" ]
    &&
      deployment.sourceRoots."services/beszel/manifests/agent.nix" == [
        "adelie"
        "pi"
        "workstation"
      ]
    &&
      deployment.sourceRoots."services/ntfy/manifests/notify.nix" == [
        "adelie"
        "pi"
        "workstation"
      ]
    && deployment.machineRoots."services/caddy/ansible" == [ "pi" ]
    && deployment.machineRoots."services/glance/ansible" == [ "pi" ]
    && deployment.machineRoots."services/beszel/ansible/agent" == [ "pi" ]
    && deployment.machineRoots."services/beszel/ansible/hub" == [ "pi" ]
    && deployment.machineRoots."services/ntfy/ansible" == [ "pi" ]
    && deployment.machineRoots."services/bazarr" == [ "workstation" ]
    && deployment.machineRoots."services/jellyseerr" == [ "workstation" ]
    && deployment.machineRoots."services/lidarr" == [ "workstation" ]
    && deployment.machineRoots."services/prowlarr" == [ "workstation" ]
    && deployment.machineRoots."services/qbittorrent" == [ "workstation" ]
    && deployment.machineRoots."services/radarr" == [ "workstation" ]
    && deployment.machineRoots."services/recyclarr" == [ "workstation" ]
    && deployment.machineRoots."services/sonarr" == [ "workstation" ]
    && deployment.machineRoots."infra/common/ansible" == [ "pi" ]
    && deployment.machineRoots."infra/adelie" == [ "adelie" ]
    && deployment.machineRoots."infra/pi" == [ "pi" ]
    && deployment.machineRoots."infra/workstation" == [ "workstation" ];

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
