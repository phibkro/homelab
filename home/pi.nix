{ inputs, ... }:

# Minimal home-manager wrapper for pi. Pi was previously system-only
# (no home-manager activation, nori had only system PATH), which forced
# every operator-CLI tool into modules/common/base.nix systemPackages
# just so ssh-into-pi-and-grep workflows worked. Adding home-manager
# here lets pi share home/core.nix with workstation + Mac — same
# operator baseline (starship, programs.git, sops/age/claude-code,
# just/ripgrep/tmux) on every interactive shell.
#
# Cost: one extra activation step per `nixos-rebuild` on pi, ~50-100 MB
# closure growth. Acceptable on Pi 4 (8 GiB RAM, USB SSD).
#
# Activation runs as part of nixos-rebuild, same as workstation —
# composes via the home-manager-as-NixOS-module wiring below.

{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "hm-backup";

    users.nori = {
      imports = [ ./core.nix ];

      home.stateVersion = "25.11";
      programs.home-manager.enable = true;
    };
  };
}
