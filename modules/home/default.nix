{
  inputs,
  nixpkgs,
  home-manager,
}:

# Standalone home-manager configurations for non-NixOS machines.
#
# NixOS machines embed home-manager as a NixOS module inside their
# own machines/<n>/default.nix; these standalone entries are only
# for machines where the host OS isn't NixOS (Mac).
#
# Activate with `home-manager switch --flake .#<name>`.

let
  # Mac pkgs with allowUnfree so claude-code (unfree license)
  # resolves. Same pattern as `pkgsUnfree` in flake.nix for the
  # dev shell.
  darwinPkgs = import nixpkgs {
    system = "x86_64-darwin";
    config.allowUnfree = true;
  };
in
{
  homeConfigurations.macbook = home-manager.lib.homeManagerConfiguration {
    pkgs = darwinPkgs;
    # Pass `inputs` to home-manager modules so home/claude-code/
    # can reach the third-party-skill flake inputs (superpowers,
    # caveman, anthropics-skills). Workstation gets the same via
    # extraSpecialArgs in its NixOS-side home-manager wrapper.
    extraSpecialArgs = { inherit inputs; };
    modules = [ ../../machines/macbook/home.nix ];
  };
}
