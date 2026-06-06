{ pkgs, ... }:

# pavilion — home-manager config for `nori`.
#
# Minimal: this is the agent quarantine host, not a workstation.
# Operator SSHs in from a privileged-tier machine to run
# `nixpkgs-agent/solve.sh <package>`; the agent fires under
# `box --pi --pwd-ro` and either lands a diff or doesn't.
#
# Notably absent vs machines/workstation/home.nix:
#   * No desktop (Hyprland, fuzzel, ghostty) — headless
#   * No claude-code — operator's trusted hands stay on workstation;
#     pavilion only runs sandboxed agents (pi)
#   * No nixpkgs-master overlays, no zen-browser, no themes
#
# `pi` + `box` (and pagu-box itself) come via system PATH from
# home/claude-code/default.nix on the PCs — but pavilion doesn't
# import that module. Wire what we need directly here.

{
  # Shared operator CLI baseline (starship, git, direnv, just, ripgrep,
  # comma, tmux, sops/age, devenv, nixd, nil). `just` here is
  # load-bearing for `just remote pavilion rebuild` from workstation.
  imports = [ ../../home/core.nix ];

  home.packages = with pkgs; [
    # Pavilion-only extras on top of core.
    fd
    jq
    bat

    # The agent harness needs `nix-build` and friends — those come
    # from the system NixOS install (boot.kernel + nix-daemon), not
    # this module. Nothing extra to bring in here.
  ];

  # `pi` (badlogic/pi-mono) + `pagu-box` + `box` alias are added
  # separately once those wrappers land in a shared module.
  # Today they live in home/claude-code/default.nix, which we
  # explicitly DON'T import here (claude-code itself shouldn't run on
  # pavilion). Follow-up: extract the agent-tooling subset of
  # claude-code/default.nix into a small shared module that pavilion
  # CAN import without dragging claude-code along.
  #
  # Until that extraction, the operator can run `pi` via:
  #   nix run github:phibkro/pagu-box#default -- --profile=strict --pi -- \
  #     nix shell github:badlogic/pi-mono -c pi …
  # — i.e. fully via flake, no host-side install. Slower (cold cache)
  # but doesn't require this module to know about either tool.

  home.stateVersion = "26.05";
}
