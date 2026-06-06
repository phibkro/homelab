{ pkgs, ... }:

# aurora — home-manager config for nori.
#
# Minimal. aurora is a single-role ML offload host; operator SSHs in
# from a privileged-tier machine for occasional maintenance. No
# desktop, no claude-code, no agent harnesses — that's pavilion's job.

{
  home.packages = with pkgs; [
    git
    ripgrep
    fd
    jq
    bat
    # nvtop / nvitop come from the system NixOS install when
    # services.xserver.videoDrivers includes nvidia. Operator can
    # `nix run nixpkgs#nvitop` ad-hoc when investigating GPU load.
  ];

  home.stateVersion = "26.05";
}
