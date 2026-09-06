/*
  ── Machines ────────────────────────────────────────────────────────
  Enumeration, identity registry, and mkHost wrapper all live at
  `lib/machines.nix`. This flake-part imports the factory
  and surfaces its `nixosConfigurations` at the flake level.
  See `lib/machines.nix` for the schema, registry, and
  rationale.
*/
{ inputs, ... }:
let
  machines = import ../machines.nix {
    inherit (inputs.nixpkgs) lib;
    inherit inputs;
  };
in
{
  flake = {
    inherit (machines) nixosConfigurations;
    lib.noriInventory = machines.inventory.public;
    lib.noriDeployment = machines.inventory.deployment;
  };
}
