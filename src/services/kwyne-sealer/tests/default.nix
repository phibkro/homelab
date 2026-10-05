{ bundle }:
let
  root = toString ../../../..;
  flake = builtins.getFlake root;
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
in
import ./nixos.nix {
  inherit pkgs;
  inherit (pkgs) lib;
  inputs = flake.inputs // {
    self = flake;
  };
  bundle = builtins.path {
    path = /. + bundle;
    name = "authority-sealed-sealer.js";
  };
}
