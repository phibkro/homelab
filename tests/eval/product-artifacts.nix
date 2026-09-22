{
  inputs,
  lib,
  ...
}:

/**
  Personal-product artifact boundary.

  Application repositories own their Cloudflare builds and deployments.
  Homelab hosts must not rebuild mutable application source at activation or
  through operator-triggered systemd units.
*/
let
  inventory = inputs.self.lib.noriInventory;
  artifactWorkloads = lib.filterAttrs (_: workload: workload ? artifact) inventory.workloads;
in
if artifactWorkloads == { } then
  "ok — personal products have no homelab-side artifact consumers"
else
  throw ''
    Homelab-side product artifact consumers remain:
    ${builtins.toJSON (lib.attrNames artifactWorkloads)}
  ''
