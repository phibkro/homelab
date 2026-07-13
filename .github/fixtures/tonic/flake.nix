{
  description = "Package-contract fixture for the private tonic flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          backend = pkgs.writeShellApplication {
            name = "tonic";
            text = "exit 0";
          };
          pwa = pkgs.runCommand "tonic-pwa-contract-fixture" { } ''
            mkdir -p "$out/share/tonic-pwa"
          '';
        }
      );
    };
}
