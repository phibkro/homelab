_:

/**
  Shared home-manager baseline for operator-attached PCs (workstation +
  macbook). Sits between core.nix (everything, pi included) and per-
  machine home.nix. Rule: heavy closures (Node/Rust/Electron toolchains)
  live here so the pi's anti-write SSD doesn't carry them.

  Architecture:
    workstation/home.nix → imports pc.nix → imports core.nix
    macbook/home.nix     → imports pc.nix → imports core.nix
    pi/home.nix          → imports core.nix directly

  Adding a third PC = its home.nix imports pc.nix. Promoting something
  from one PC into "every PC" = move it here.
*/
{
  imports = [
    ./core.nix
    ./claude-code # CLI + settings.json + skills (~300 MB Node closure)
    ./hermes # Hermes Agent CLI (Linux-only; skips cleanly on Mac)
  ];
}
