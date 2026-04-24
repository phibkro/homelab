{ config, pkgs, lib, ... }:

{
  # --- nix ---------------------------------------------------------------

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "@wheel" ];
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
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # --- users -------------------------------------------------------------

  users.users.nori = {
    isNormalUser = true;
    description = "Philip";
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # Mac laptop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINZj3DMqIjSV04Yiafw4Td0lQAoQyITCdRS9V/78XrrO 71797726+phibkro@users.noreply.github"
    ];
  };

  # Root login is disabled over SSH; wheel-with-password is the recovery path.
  security.sudo.wheelNeedsPassword = true;

  # --- ssh ---------------------------------------------------------------

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # --- tailscale ---------------------------------------------------------

  # First-boot auth is manual: `sudo tailscale up --ssh`.
  # Later we move to services.tailscale.authKeyFile via sops-nix.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
  };

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

  # --- firewall ----------------------------------------------------------

  networking.firewall.enable = true;

  # --- versioning --------------------------------------------------------

  # stateVersion is a *migration* marker, not the nixpkgs version.
  # Do not bump this casually. It captures the defaults in effect when the
  # system was first installed so stateful services don't silently reshape.
  system.stateVersion = "25.11";
}
