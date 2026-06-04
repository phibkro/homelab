{ pkgs, inputs, ... }:

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
#   home-manager switch -b hm-backup --flake ~/Documents/nix-migration#macbook
#
# The `-b hm-backup` is load-bearing: standalone home-manager has no
# `home.backupFileExtension` option (that's NixOS-module-only). Without
# it, any first-rebuild after a tool (Claude Code, etc.) wrote into
# ~/.claude/ or ~/.config/ aborts with "Existing file ... would be
# clobbered". With it, conflicting files get renamed `<name>.hm-backup`
# and activation proceeds.
#
# Update inputs:
#   nix flake update --flake ~/Documents/nix-migration
#   home-manager switch -b hm-backup --flake ~/Documents/nix-migration#macbook

{
  imports = [
    ../pc.nix
    inputs.pagu-box.homeManagerModules.default
  ];

  # Sandboxed launcher for any CLI process (claude, aider, opencode, …).
  # See https://github.com/phibkro/pagu-box. Use `pagu-box --profile=NAME
  # <cmd>` — defaults to the `default` profile (allow-by-default, secret
  # deny-list, network allowed) which is the equivalent of the
  # workstation's `claude-box` shape.
  programs.pagu-box.enable = true;

  home.username = "nori";
  home.homeDirectory = "/Users/nori";

  # `stateVersion` is a *migration* marker, not the home-manager
  # version. Don't bump unless you've read the release notes.
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # CLI tooling Mac-specific to this host. Cross-platform tooling
    # for every operator-PC (claude-code + happy-coder) lives in
    # machines/pc.nix → modules/claude-code/. Cross-machine including
    # pi (starship, programs.git, comma, sops CLI, etc.) lives in
    # machines/core.nix.

    gh

    # JS/TS runtime + tooling
    bun
    pnpm

    ffmpeg
    tree-sitter

    # === GUI apps ===
    # On Mac, home-manager's targets.darwin.linkApps activation
    # script symlinks Nix-installed .app bundles into
    # ~/Applications/Nix Apps/ so Spotlight / Launchpad pick
    # them up. Built-in, no extra config needed.
    localsend

    # handbrake — GUI video transcoder. nixpkgs lists x86_64-darwin in
    # meta.platforms but marks the package `broken` there (refuses to
    # eval), so it can't come from Nix on this host. Workstation gets
    # pkgs.handbrake (cached, Linux). Brew: `brew install --cask handbrake`.
    #
    # ghostty — has no Darwin meta.platforms in nixpkgs (Linux-only
    # build). Install via brew: `brew install --cask ghostty`.
    #
    # utm — NOT in nixpkgs (proprietary Mac VM frontend).
    # Brew: `brew install --cask utm`.
    #
    # tailscale — macOS Tailscale uses NetworkExtension framework, not
    # a userspace daemon. The App-Store / brew-cask version provides
    # both the daemon (system-level integration) and the CLI.
    # Installing pkgs.tailscale here would shadow the App's CLI with
    # potential version drift. Brew: `brew install --cask tailscale`.
    # Sign in once via the menubar; tailnet hostnames + magicDNS work
    # thereafter. Workstation runs full services.tailscale.enable via
    # NixOS module; Mac standalone home-manager has no equivalent.
    #
    # moonlight — game-stream client for the Sunshine host on the
    # workstation (remote DaVinci Resolve editing over the tailnet).
    # GUI cask, not usable from nixpkgs on this Darwin host.
    # Brew: `brew install --cask moonlight`. Add the host by tailnet
    # name `workstation` if mDNS doesn't auto-list it, and pair via the
    # Sunshine web UI at https://workstation:47990. Host config:
    # modules/desktop/sunshine.nix.
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

  # JetBrains Mono Nerd Font installed into ~/Library/Fonts/ so macOS
  # Font Book + Ghostty pick it up. Each .ttf gets symlinked
  # individually (recursive = true) — preserves the dir for any
  # non-Nix fonts you drop in alongside.
  #
  # Pair with Ghostty config:
  #   font-family = JetBrainsMono Nerd Font
  # in ~/Library/Application Support/com.mitchellh.ghostty/config
  # (Ghostty isn't currently managed by home-manager — set this once
  # imperatively, or wire `programs.ghostty` later).
  home.file."Library/Fonts/JetBrainsMonoNerdFont" = {
    source = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono";
    recursive = true;
  };

  programs.home-manager.enable = true;
}
