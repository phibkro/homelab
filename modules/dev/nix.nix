{ pkgs, lib }:
# Nix language fragment. Toolchain only — `nix` itself is assumed to
# be present on the system (consumers without nix can't run a flake
# devShell anyway, so packaging it would be circular).
{
  buildInputs = with pkgs; [
    nixfmt # rfc-166 style (the unified `nixfmt` package — formerly nixfmt-rfc-style)
    nil # LSP — Zed auto-detects via PATH
    statix # anti-pattern + dead-let lints
    deadnix # unused-binding detection
    nix-tree # interactive store-graph spelunking
    nh # ergonomic rebuild front-end (`nh os switch .`)
  ];

  claude.permissions.allow = [
    "Bash(nix *)"
    "Bash(nh *)"
    "Bash(just *)"
    "Bash(nixfmt *)"
    "Bash(statix *)"
    "Bash(deadnix *)"
    "Bash(nix-tree *)"
  ];

  shellHook = ''echo "[dev/nix] nixfmt + nil + statix + deadnix + nh"'';
}
