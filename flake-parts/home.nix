/*
  ── Home configurations ─────────────────────────────────────────────
  Standalone home-manager entries for non-NixOS machines (Mac). The
  factory lives at `modules/home/default.nix` and returns a
  `homeConfigurations` attrset.
*/
{ inputs, ... }:
let
  machines = import ../modules/machines {
    inherit (inputs.nixpkgs) lib;
    inherit inputs;
  };
in
{
  flake.homeConfigurations =
    (import ../modules/home {
      inherit inputs;
      nixpkgs = inputs.nixpkgs-stable;
      home-manager = inputs.home-manager-darwin;
      inherit (machines) standaloneHomes;
    }).homeConfigurations;
}
