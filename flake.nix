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

    # Per-user config (desktop phase). Tracks nixos-unstable in lockstep
    # with nixpkgs; re-pin deliberately on `nix flake update`.
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Zen browser. Not in nixpkgs; consumed via upstream community flake.
    # `.default` tracks rolling Twilight; pivot to `.beta` or `.specific`
    # if Twilight churn becomes annoying.
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      disko,
      sops-nix,
      home-manager,
      zen-browser,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkHost =
        hostPath:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [ hostPath ];
        };
    in
    {
      nixosConfigurations = {
        vm-test = mkHost ./hosts/vm-test;
        nori-station = mkHost ./hosts/nori-station;
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;

      # Quality gates. Run `nix flake check` to validate everything:
      #   - host configs evaluate (caught by nixosConfigurations check)
      #   - statix flags Nix anti-patterns
      #   - deadnix flags unused bindings
      #   - format-check fails on unformatted .nix files
      checks.${system} = {
        # cd into the source so statix picks up `statix.toml` (looked up
        # from the working directory, not the path argument).
        statix = pkgs.runCommandLocal "statix" { } ''
          cd ${./.}
          ${pkgs.statix}/bin/statix check . > $out
        '';

        # --no-lambda-pattern-names: NixOS module convention is to
        # declare `{ config, lib, pkgs, ... }:` even when not all are
        # used; tolerate that. Still flags genuine unused
        # let-bindings and other dead code.
        deadnix = pkgs.runCommandLocal "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names ${./.}
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
