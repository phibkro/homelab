{
  inputs,
  lib,
  ...
}:

/**
  Source-only Adelie admission contract.

  This proves the evaluated closure boundary. It does not prove physical disk
  identity, installation, boot, network enrollment, or runtime behavior.
*/
let
  config = inputs.self.nixosConfigurations.adelie.config;
  inventory = inputs.self.lib.noriInventory;
  deployment = inputs.self.lib.noriDeployment;
  services = config.systemd.services;
  timers = config.systemd.timers;

  workloadsCorrect =
    inventory.hosts.adelie.workloads == [
      "beszel-agent"
      "node-exporter"
    ];

  diskBoundaryCorrect =
    lib.attrNames config.disko.devices.disk == [ "main" ]
    &&
      config.disko.devices.disk.main.device
      == "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_1TB_S7HDNU0L409926V"
    &&
      lib.attrNames config.fileSystems == [
        "/"
        "/.snapshots"
        "/boot"
        "/home"
        "/nix"
        "/var/lib"
      ]
    && config.nori.fs == { };

  runtimeBoundaryCorrect =
    builtins.hasAttr "beszel-agent" services
    && builtins.hasAttr "prometheus-node-exporter" services
    && builtins.hasAttr "vector" services
    && !(builtins.hasAttr "attic-cache-seed" services)
    && !(builtins.hasAttr "attic-cache-watch" services)
    && !(builtins.hasAttr "attic-cache-seed" timers)
    && !(builtins.hasAttr "attic-cache-watch" timers)
    && !(builtins.hasAttr "atticd" services)
    && !(builtins.hasAttr "restic-target-directories" services);

  secretBoundaryCorrect = config.sops.secrets == { };

  bootstrapNetworkCorrect = config.networking.useDHCP && !config.networking.wireless.enable;

  deploymentBoundaryCorrect =
    deployment.targets.adelie == {
      kind = "nixos";
      profiles = [
        "base"
        "log-forwarder"
        "observability-agent"
      ];
      workloads = [
        "beszel-agent"
        "node-exporter"
      ];
      buildAttribute = "nixosConfigurations.adelie.config.system.build.toplevel";
      planCommand = null;
      applyCommand = null;
      verifyCommand = null;
    };
in
if
  workloadsCorrect
  && diskBoundaryCorrect
  && runtimeBoundaryCorrect
  && secretBoundaryCorrect
  && bootstrapNetworkCorrect
  && deploymentBoundaryCorrect
then
  "ok — Adelie evaluates as a minimal source-only host with no activation or portable-storage authority"
else
  throw ''
    Adelie source admission contract failed.
    Workloads:  ${toString workloadsCorrect}
    Disk:       ${toString diskBoundaryCorrect}
    Runtime:    ${toString runtimeBoundaryCorrect}
    Secrets:    ${toString secretBoundaryCorrect}
    Network:    ${toString bootstrapNetworkCorrect}
    Deployment: ${toString deploymentBoundaryCorrect}
  ''
