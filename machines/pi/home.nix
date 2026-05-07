{ ... }:

# Pure home-manager module — pi user content (currently minimal: just
# the core baseline). The home-manager-as-NixOS-module wrapper lives
# in the sibling default.nix.
#
# Why pi has a home.nix at all: previously system-only, every operator-
# CLI tool had to live in modules/common/base.nix systemPackages just
# so ssh-into-pi-and-grep workflows worked. Adding home-manager here
# lets pi share machines/core.nix with workstation + Mac — same
# operator baseline (starship, programs.git, sops/age/claude-code,
# just/ripgrep/tmux) on every interactive shell.
#
# Cost: one extra activation step per nixos-rebuild on pi, ~50-100 MB
# closure growth. Acceptable on Pi 4 (8 GiB RAM, USB SSD).

{
  imports = [ ../core.nix ];

  home.stateVersion = "25.11"; # match host's system.stateVersion
  programs.home-manager.enable = true;
}
