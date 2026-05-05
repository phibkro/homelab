{ lib, pkgs, ... }:

let
  # Status line script. Keeps the operator's content intact (jq-based
  # parse of the JSON Claude Code pipes in) but injects PATH so jq + git
  # are guaranteed available — declarative deps beats `nix-shell -p jq`
  # at runtime.
  statuslineScript = pkgs.writeShellScript "claude-statusline" ''
    PATH=${
      lib.makeBinPath [
        pkgs.jq
        pkgs.git
        pkgs.coreutils
      ]
    }:$PATH

    # Read JSON input from stdin
    input=$(cat)

    # Extract values
    model=$(echo "$input" | jq -r '.model.display_name')
    current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
    remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
    output_style=$(echo "$input" | jq -r '.output_style.name // empty')

    # Get git branch if in a git repo (skip optional locks for performance)
    git_branch=""
    if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
        git_branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
        if [ -n "$git_branch" ]; then
            git_branch=" ($git_branch)"
        fi
    fi

    # Build the status line
    status="$model"

    # Add output style if not default
    if [ -n "$output_style" ] && [ "$output_style" != "default" ]; then
        status="$status [$output_style]"
    fi

    status="$status | $current_dir$git_branch"

    # Add context remaining if available
    if [ -n "$remaining" ]; then
        # Color-code thresholds preserved from operator's script. Currently
        # informational only — string assembly below uses plain text.
        if [ "''${remaining%.*}" -lt 20 ]; then
            context_color="red"
        elif [ "''${remaining%.*}" -lt 50 ]; then
            context_color="yellow"
        else
            context_color="green"
        fi
        status="$status | Context: ''${remaining}%"
    fi

    echo "$status"
  '';

  # Settings.json — single attrset, rendered to JSON below. Each key
  # documented inline so the rationale lives next to the value, not in
  # the commit history.
  settings = {
    # Enables IDE autocomplete + schema validation when editing this
    # file (or its rendered output) in editors that pick up the
    # JSON-Schema.org store.
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";

    theme = "auto";

    # Default thinking depth. "high" gives Opus more headroom for
    # deeper structural reasoning by default; flip to "medium" if
    # latency starts to bite.
    effortLevel = "high";

    # Skip the warning prompt when launching with --dangerously-skip-
    # permissions. Operator runs Claude in a trusted dev loop where
    # the warning is friction, not signal.
    skipDangerousModePermissionPrompt = true;

    # MCP server posture: opt-in only.
    #   * allowManagedMcpServersOnly:    only servers explicitly
    #     allow-listed elsewhere are loadable. Blocks ad-hoc loads.
    #   * enableAllProjectMcpServers:    do NOT auto-trust project-
    #     level .mcp.json files. Each project's MCP set has to be
    #     opted in explicitly via enabledMcpjsonServers.
    # Together these cap MCP-driven context consumption — large
    # tool surfaces (Linear, Canva, etc.) only load when actually
    # needed for the task at hand.
    allowManagedMcpServersOnly = true;
    enableAllProjectMcpServers = false;

    # Status line: shown in Claude Code's footer/header. Path is the
    # nix-store hash of the script above; deterministic + reproducible
    # across rebuilds. No symlink in ~/.claude/ needed — Claude reads
    # from the absolute path directly.
    statusLine = {
      type = "command";
      command = "${statuslineScript}";
    };
  };
in
{
  # Claude Code agent configuration — declarative + reusable.
  #
  # Same pattern as the rest of modules/desktop: home-manager links
  # files from the repo into ~/. The repo is the source of truth; each
  # operator-attached host (workstation today, future Mac/laptop) picks
  # up the same agent config via home-manager-on-NixOS or home-manager-
  # standalone (Mac).
  #
  # ── What's managed here ─────────────────────────────────────────
  #   ~/.claude/skills/        — recursive: every skill folder under
  #                              modules/desktop/claude/skills/ becomes
  #                              available in Claude Code automatically.
  #                              Add a new skill = create folder + rebuild.
  #   ~/.claude/settings.json  — generated from the `settings` attrset
  #                              above. Schema-validated; see
  #                              json.schemastore.org/claude-code-settings.
  #                              Includes statusLine, MCP posture,
  #                              effort level, dangerous-mode prompt skip.
  #
  # Future additions follow the same shape:
  #   ~/.claude/CLAUDE.md      — user-level CLAUDE.md (cross-project
  #                              preferences, persona, working-style)
  #   ~/.claude/agents/        — sub-agents
  #
  # ── What's NOT managed here ─────────────────────────────────────
  # Dynamic state — accumulates over sessions, isn't config:
  #   ~/.claude/projects/<project>/memory/* — per-project memory
  #   ~/.claude/projects/<project>/todos/*  — per-session todos
  #   ~/.claude/sessions/*                  — session history
  #   ~/.claude.json                        — user-scope MCP servers,
  #                                           oauth tokens, runtime
  #                                           caches; mutated on every
  #                                           launch, can't be home-
  #                                           managed wholesale.
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

    # Generated JSON, not a source file. The `settings` attrset above
    # is the source of truth; the rendered file is reproducible from
    # any rebuild. Editing ~/.claude/settings.json directly would lose
    # the change on the next home-manager activation.
    ".claude/settings.json".text = builtins.toJSON settings;
  };
}
