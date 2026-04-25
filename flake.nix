{
  description = "nori infrastructure (NixOS) — nori-station and future lab hosts";

  # Pinned to nixos-unstable because nori-station has an RTX 5060 Ti
  # (Blackwell), whose driver lands in recent nixpkgs. Treat unstable +
  # flake.lock as the de-facto stable channel; re-pin deliberately.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Planned additions (introduced when needed):
    #   sops-nix       — secrets (age / ssh-to-age)
    #   home-manager   — per-user config (desktop phase)
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, ... }@inputs:
    let
      system = "x86_64-linux";
      mkHost = hostPath: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ hostPath ];
      };
    in {
      nixosConfigurations = {
        vm-test      = mkHost ./hosts/vm-test;
        nori-station = mkHost ./hosts/nori-station;
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
