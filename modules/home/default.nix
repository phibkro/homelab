{
  inputs,
  nixpkgs,
  home-manager,
  standaloneHomes,
}:

/**
  Standalone home-manager configurations for non-NixOS machines.

  NixOS machines embed home-manager as a NixOS module inside their
  own `modules/machines/<n>/default.nix`; these standalone entries are only
  for machines where the host OS isn't NixOS (Mac).

  Activate with `home-manager switch --flake .#<name>`.
*/
{
  homeConfigurations = builtins.mapAttrs (
    _name: host:
    home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = host.homeSystem;
        config.allowUnfree = true;
      };
      extraSpecialArgs = { inherit inputs; };
      modules = [ host.homeModule ];
    }
  ) standaloneHomes;
}
