{ pkgs }:
/**
  Nix language fragment. Toolchain only — `nix` itself is assumed to
  be present on the system (consumers without nix can't run a flake
  devShell anyway, so packaging it would be circular).
*/
{
  buildInputs = with pkgs; [
    nixfmt # rfc-166 style (the unified `nixfmt` package — formerly nixfmt-rfc-style)
    /*
      Two LSPs side-by-side. Editors (Zed's Nix extension, neovim's
      nvim-lspconfig, etc.) typically pick one or both; having both
      available means the editor's choice doesn't gate the dev shell.
    */
    nil # nil-lang LSP — fast, mature, weaker flake support
    nixd # nixd LSP — deeper flake / NixOS option / home-manager awareness
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

  shellHook = ''echo "[dev/nix] nixfmt + nil + nixd + statix + deadnix + nh"'';
}
