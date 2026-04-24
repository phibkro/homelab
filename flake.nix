{
  description = "nori infrastructure (NixOS + home configurations)";

  # nixos-unstable chosen initially because nori-station has an RTX 5060 Ti
  # (Blackwell), whose driver support lands in recent kernels/nvidia packages.
  # Revisit and pin to a stable channel once the driver situation is verified
  # on the target machine.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Added once service modules start referencing them:
    #   sops-nix       — secrets management (age / ssh-to-age)
    #   home-manager   — per-user configuration (desktop phase)
    #   nixos-hardware — hardware-specific tweaks (zen4, nvidia)
    #   disko          — declarative partitioning (post first install)
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    in {
      nixosConfigurations = {
        # Populated in a later phase once the inventory informs what services
        # this host needs to run. Until then the flake intentionally builds
        # nothing so the repo stays evaluable on any machine.
        #
        # nori-station = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   specialArgs = { inherit inputs; };
        #   modules = [
        #     ./hosts/nori-station
        #   ];
        # };
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
