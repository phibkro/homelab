{ pkgs, ... }:

# aurora — home-manager config for nori.
#
# Minimal. aurora is a single-role ML offload host; operator SSHs in
# from a privileged-tier machine for occasional maintenance. No
# desktop, no claude-code, no agent harnesses — that's pavilion's job.
#
# Imports the shared core: starship + git + direnv + the operator CLI
# baseline (just, ripgrep, comma, tmux, sops/age, devenv, nixd, nil) —
# matches what every other host's operator session has. `just` here is
# load-bearing for `just remote aurora rebuild` from workstation.

{
  imports = [ ../../home/core.nix ];

  home.packages = with pkgs; [
    fd
    jq
    bat
    # nvtop / nvitop come from the system NixOS install when
    # services.xserver.videoDrivers includes nvidia. Operator can
    # `nix run nixpkgs#nvitop` ad-hoc when investigating GPU load.
  ];

  home.stateVersion = "26.05";
}
