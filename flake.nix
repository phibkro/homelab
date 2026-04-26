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

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Planned additions (introduced when needed):
    #   home-manager   — per-user config (desktop phase)
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
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

      formatter.${system} = pkgs.nixfmt-rfc-style;

      # Quality gates. Run `nix flake check` to validate everything:
      #   - host configs evaluate (caught by nixosConfigurations check)
      #   - statix flags Nix anti-patterns
      #   - deadnix flags unused bindings
      #   - format-check fails on unformatted .nix files
      checks.${system} = {
        statix = pkgs.runCommandLocal "statix" { } ''
          ${pkgs.statix}/bin/statix check ${./.} > $out
        '';

        deadnix = pkgs.runCommandLocal "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail ${./.}
          touch $out
        '';

        format = pkgs.runCommandLocal "format" { } ''
          cd ${./.}
          ${pkgs.nixfmt-rfc-style}/bin/nixfmt --check $(find . -name '*.nix' -not -path '*/result/*')
          touch $out
        '';
      };
    };
}
