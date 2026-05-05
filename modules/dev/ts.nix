{ pkgs, lib }:
# TypeScript language fragment. Toolchain only: tsc + LSP + voidzero
# tools (oxlint, oxfmt). Runtime (`node` / `bun`) and package manager
# (`pnpm`) are deliberately *not* included — they're separate
# fragments to compose explicitly per the project's choice.
#
# voidzero (oxc) replaces the eslint+prettier combo: oxlint is
# ~50× faster than eslint, oxfmt is the prettier-compat formatter
# in the same family. Both are in active development; once the `oxc`
# umbrella package lands in nixpkgs, fold these into a single dep.
{
  buildInputs = with pkgs; [
    typescript # tsc — bundled node, no system node needed for tsc itself
    typescript-language-server # tsls — Zed picks up via PATH
    oxlint # voidzero linter (replaces eslint)
    oxfmt # voidzero formatter (replaces prettier)
  ];

  claude.permissions.allow = [
    "Bash(tsc *)"
    "Bash(oxlint *)"
    "Bash(oxfmt *)"
    "Bash(typescript-language-server *)"
  ];

  shellHook = ''echo "[dev/ts] tsc + tsls + oxlint + oxfmt"'';
}
