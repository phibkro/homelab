{ pkgs, lib }:
# Claude Code consent fragment.
#
# Including this fragment in a dev shell's `modules` list tells the
# composer to materialize `.claude/settings.json` from the union of
# `claude.*` contributions across every module in the list. Without
# this fragment, those contributions are still collected (so each
# module can declare them unconditionally) but never written — the
# same dev shell stays usable for collaborators on other editors,
# without spurious `.claude/` files appearing in their working tree.
#
# The materialized file is a symlink into /nix/store; it's already
# matched by `.gitignore`'s `.claude/*` rule (the user-level skills
# negation `!.claude/skills/` is the only exception). Project-specific
# overrides go in `.claude/settings.local.json` per Claude Code's
# normal layered-config precedence.
{
  buildInputs = with pkgs; [
    claude-code # the `claude` CLI itself, on PATH inside the shell
  ];

  claude.permissions.allow = [
    "Bash(claude *)"
  ];

  shellHook = ''echo "[dev/claude-code] settings.json materialized; .claude/settings.local.json layered on top"'';
}
