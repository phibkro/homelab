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
  imports = [ ./core.nix ];

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
    # git itself comes from `programs.git.enable` in core.nix.
    gh

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

  # Caddy on workstation signs *.nori.lan with its local CA, which
  # macOS keychain doesn't ship and Node's CA bundle ignores by
  # default. Point Node clients (immich-cli, claude-code MCP fetches,
  # arbitrary `npm`/`bun` scripts hitting nori.lan endpoints) at the
  # cert committed in the repo. The `${...}` interpolation copies the
  # cert into /nix/store at build time, so the path stays valid even
  # if the working tree moves.
  #
  # If you also want curl/Safari to trust the CA without
  # NODE_EXTRA_CA_CERTS' Node-only scope, install it into the system
  # trust store imperatively (one-shot, not declarative without
  # nix-darwin):
  #   sudo security add-trusted-cert -d -r trustRoot \
  #     -k /Library/Keychains/System.keychain \
  #     ~/Documents/nix-migration/modules/server/caddy-local-ca.crt
  home.sessionVariables = {
    NODE_EXTRA_CA_CERTS = "${../../modules/server/caddy-local-ca.crt}";
  };

  # Hack Nerd Font installed into ~/Library/Fonts/ so macOS Font Book
  # + Ghostty pick it up. Each .ttf gets symlinked individually
  # (recursive = true) — preserves the dir for any non-Nix fonts you
  # drop in alongside.
  #
  # Pair with Ghostty config:
  #   font-family = "Hack Nerd Font"
  # in ~/Library/Application Support/com.mitchellh.ghostty/config
  # (Ghostty isn't currently managed by home-manager — set this once
  # imperatively, or wire `programs.ghostty` later).
  home.file."Library/Fonts/HackNerdFont" = {
    source = "${pkgs.nerd-fonts.hack}/share/fonts/truetype/NerdFonts/Hack";
    recursive = true;
  };

  programs.home-manager.enable = true;
}
