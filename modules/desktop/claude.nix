_: {
  # Claude Code agent configuration — declarative + reusable.
  #
  # Same pattern as the rest of modules/desktop: home-manager symlinks
  # files from the repo into ~/. The repo is the source of truth; each
  # operator-attached host (workstation today, future Mac/laptop) picks
  # up the same agent config via home-manager-on-NixOS or home-manager-
  # standalone (Mac).
  #
  # ── What's managed here ─────────────────────────────────────────
  #   ~/.claude/skills/      — recursive: every skill folder under
  #                            modules/desktop/claude/skills/ becomes
  #                            available in Claude Code automatically.
  #                            Add a new skill = create folder + rebuild.
  #
  # Future additions follow the same shape:
  #   ~/.claude/CLAUDE.md    — user-level CLAUDE.md (cross-project
  #                            preferences, persona, working-style)
  #   ~/.claude/settings.json — user-level permissions, hooks, env
  #   ~/.claude/agents/      — sub-agents
  #
  # ── What's NOT managed here ─────────────────────────────────────
  # Dynamic state — accumulates over sessions, isn't config:
  #   ~/.claude/projects/<project>/memory/* — per-project memory
  #   ~/.claude/projects/<project>/todos/*   — per-session todos
  #   ~/.claude/sessions/*                   — session history
  # Project-level config (`<project>/.claude/`) stays per-project; this
  # module only handles the user-level agent surface.

  home-manager.users.nori.home.file = {
    # Recursive symlink: home-manager links each file under
    # ./claude/skills/<name>/SKILL.md to ~/.claude/skills/<name>/SKILL.md
    # individually. Files NOT in the source dir stay untouched in ~/,
    # so existing ~/.claude/skills/<other> from a prior setup aren't
    # clobbered (though they'd be stale — drop them manually).
    ".claude/skills" = {
      source = ./claude/skills;
      recursive = true;
    };
  };
}
