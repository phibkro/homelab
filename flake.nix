{
  description = "nori infrastructure (NixOS) — nori-station and future lab hosts";

  # Pinned to nixos-unstable because nori-station has an RTX 5060 Ti
  # (Blackwell), whose driver lands in recent nixpkgs. Revisit pinning to a
  # stable channel once Blackwell support is confirmed on stable.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Planned additions (introduced when needed):
    #   sops-nix       — secrets (age / ssh-to-age)
    #   home-manager   — per-user config (desktop phase)
    #   disko          — declarative partitioning (post first install)
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }@inputs:
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
