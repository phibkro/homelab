{
  inputs,
  lib,
  ...
}:

/**
  Personal-product artifact consumer contract.

  Mutable host-side builds are allowed only as named, owner-governed legacy
  exceptions. The runtime unit and operator deploy command both consume this
  inventory metadata instead of deriving names from directory layout.
*/
let
  inventory = inputs.self.lib.noriInventory;
  artifactWorkloads = lib.filterAttrs (_: workload: workload ? artifact) inventory.workloads;

  legacyIsGoverned = lib.all (
    workload:
    let
      artifact = workload.artifact;
      exception = artifact.legacyException;
    in
    artifact.consumer.kind == "legacy-host-build"
    && !artifact.immutable
    && exception.owner != ""
    && exception.reason != ""
    && exception.removalTrigger != ""
    && exception.verification == "tests/eval/product-artifacts.nix"
  ) (lib.attrValues artifactWorkloads);

  consumerExists = lib.all (
    workload:
    let
      hostName = lib.head workload.hosts;
      unitName = workload.artifact.consumer.unit;
    in
    builtins.hasAttr unitName inputs.self.nixosConfigurations.${hostName}.config.systemd.services
  ) (lib.attrValues artifactWorkloads);
in
if
  lib.attrNames artifactWorkloads == [
    "filmder"
    "heim"
  ]
  && legacyIsGoverned
  && consumerExists
then
  "ok — personal product artifact consumers are explicit and legacy builds are governed"
else
  throw ''
    Product artifact contract mismatch.
    Artifact workloads: ${builtins.toJSON (lib.attrNames artifactWorkloads)}
    Legacy governance: ${toString legacyIsGoverned}
    Consumers exist:   ${toString consumerExists}
  ''
