{
  config,
  pkgs,
  lib,
  ...
}:

{
  # --- nix ---------------------------------------------------------------

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # --- locale / time -----------------------------------------------------

  time.timeZone = "Europe/Oslo";
  # Locale stays en_US for English error messages / man pages / web
  # search continuity. Switch to nb_NO.UTF-8 if you want Norwegian
  # date/sort formats too.
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "no";

  # --- packages (minimal baseline shared by all hosts) ------------------

  environment.systemPackages = with pkgs; [
    bat
    curl
    dig
    fd
    git
    htop
    ripgrep
    tmux
    tree
    vim
    wget
  ];

  # nh — Yet Another Nix Helper. Wraps `nixos-rebuild` with a nicer
  # diff display, internal sudo elevation (don't prefix nh with sudo),
  # and built-in `--target-host` support for SSH-based remote
  # deployment. Replaces the rsync-then-nixos-rebuild dance with:
  #   nh os switch /tmp/nix-migration -H nori-station            # local
  #   nh os switch github:phibkro/homelab -H nori-station        # git
  #   nh os switch . -H nori-station --target-host <ip>          # remote
  programs.nh.enable = true;

  # --- firewall ----------------------------------------------------------

  networking.firewall.enable = true;

  # --- versioning --------------------------------------------------------

  # stateVersion is a *migration* marker, not the nixpkgs version.
  # Do not bump this casually. It captures the defaults in effect when the
  # system was first installed so stateful services don't silently reshape.
  system.stateVersion = "25.11";
}
