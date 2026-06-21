/*
  ── Machines ────────────────────────────────────────────────────────
  Enumeration, identity registry, and mkHost wrapper all live at
  `modules/machines/default.nix`. This flake-part imports the factory
  and surfaces its `nixosConfigurations` at the flake level.
  See `modules/machines/default.nix` for the schema, registry, and
  rationale.
*/
{ inputs, ... }:
{
  flake.nixosConfigurations =
    (import ../modules/machines {
      inherit (inputs.nixpkgs) lib;
      inherit inputs;
    }).nixosConfigurations;
}
