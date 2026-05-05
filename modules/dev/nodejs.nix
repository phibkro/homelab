{ pkgs, lib }:
# Node.js runtime + npm. Pinned to current LTS via nodejs_22; bump
# deliberately. npm ships bundled with the nodejs derivation, so a
# project on plain npm doesn't need a separate `npm` fragment.
{
  buildInputs = with pkgs; [
    nodejs_22
  ];

  claude.permissions.allow = [
    "Bash(node *)"
    "Bash(npm *)"
    "Bash(npx *)"
  ];

  shellHook = ''echo "[dev/nodejs] node $(node --version)"'';
}
