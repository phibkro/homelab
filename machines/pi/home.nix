{ ... }:

# Pi user content — minimal, just the shared core baseline. The
# home-manager-as-NixOS-module wrapper lives in the sibling default.nix.
# Pi 4 has anti-write USB SSD; heavy packages (Node-based CLI etc.)
# stay out of core.nix and live per-machine.

{
  imports = [ ../core.nix ];

  home.stateVersion = "25.11"; # match host's system.stateVersion
  programs.home-manager.enable = true;
}
