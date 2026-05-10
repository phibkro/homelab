_:

# Shared home-manager baseline for operator-attached PCs (workstation +
# macbook). The shape that sits between machines/core.nix (every machine
# including the pi appliance) and per-machine machines/<n>/home.nix
# (machine-specific bits).
#
# What lives here vs core.nix:
#   * core.nix carries cross-platform CLI baseline (starship, git, sops
#     CLI, comma, just, ripgrep, tmux). Pi imports it; nothing in core
#     pulls heavy closures.
#   * pc.nix adds the operator-loop tooling — interactive agents, big
#     editors-as-CLI, anything that pulls Node / large Rust runtimes /
#     Electron — so the Pi's anti-write SSD doesn't carry packages it
#     can't use.
#
# Architecture:
#   workstation/home.nix → imports pc.nix → imports core.nix
#   macbook/home.nix     → imports pc.nix → imports core.nix
#   pi/home.nix          → imports core.nix directly
#
# Adding a third PC (laptop, etc.) = its home.nix imports pc.nix.
# Promoting something from a single PC into "every PC" = move it here.
{
  imports = [
    ./core.nix
    ../modules/claude-code # CLI + settings.json + skills (~300 MB Node closure)
  ];
}
