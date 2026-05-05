{ pkgs, lib }:
# Bun runtime + package manager + bundler — a single binary covering
# what Node + npm + esbuild would each provide. Compose `bun` into a
# project that pins `packageManager: "bun@..."` in package.json (e.g.
# heim's turborepo monorepo). Coexists with `nodejs` if both are
# present, but typically a project picks one runtime.
{
  buildInputs = with pkgs; [
    bun
  ];

  claude.permissions.allow = [
    "Bash(bun *)"
    "Bash(bunx *)"
  ];

  shellHook = ''echo "[dev/bun] bun $(bun --version)"'';
}
