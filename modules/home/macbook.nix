{ pkgs, ... }:

# nori on Mac (Intel x86_64-darwin) — standalone home-manager,
# no nix-darwin (yet). Migrates the daily-driver CLI tier off
# Homebrew. Brew stays for what nixpkgs doesn't ship for Darwin
# (utm, ghostty) and GUI casks that need full Spotlight
# integration / system-services (mactex, docker-desktop, etc).
#
# Channel: rides the flake's `nixpkgs` (unstable) input shared with
# the NixOS hosts. Pin a separate `nixpkgs-darwin` follow when 26.05
# stable ships — and note 26.05 is announced as the LAST nixpkgs
# release supporting x86_64-darwin (release-notes link in flake.nix).
#
# Iteration:
#   home-manager switch --flake ~/Documents/nix-migration#macbook
#
# Update inputs:
#   nix flake update --flake ~/Documents/nix-migration
#   home-manager switch --flake ~/Documents/nix-migration#macbook

{
  home.username = "nori";
  home.homeDirectory = "/Users/nori";

  # `stateVersion` is a *migration* marker, not the home-manager
  # version. Don't bump unless you've read the release notes.
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    # === secrets ===
    age
    sops

    # === git + GitHub ===
    gh
    git

    # === JS/TS runtime + tooling ===
    bun
    pnpm

    # === general CLI ===
    ffmpeg
    just
    ripgrep
    tmux
    tree-sitter

    # === AI ===
    claude-code

    # === GUI apps ===
    # On Mac, home-manager's targets.darwin.linkApps activation
    # script symlinks Nix-installed .app bundles into
    # ~/Applications/Nix Apps/ so Spotlight / Launchpad pick
    # them up. Built-in, no extra config needed.
    localsend

    # ghostty — has no Darwin meta.platforms in nixpkgs-25.11-darwin
    # (Linux-only build). Install via brew until upstream ships a
    # Darwin build: `brew install --cask ghostty`.
    #
    # utm — NOT in nixpkgs (proprietary Mac VM frontend).
    # Stays on brew: `brew install --cask utm`.
  ];

  programs.home-manager.enable = true;
}
