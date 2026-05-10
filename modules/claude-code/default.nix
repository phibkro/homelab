{
  inputs,
  lib,
  pkgs,
  ...
}:

# Claude Code agent — declarative + reusable. Pure home-manager module
# imported via machines/pc.nix on every operator-attached PC (workstation
# + macbook). The Pi appliance does NOT import this — pi has no operator
# agent loop, just servers, and the claude-code Node closure shouldn't
# land on pi's anti-write SSD.
#
# ── What's managed here ─────────────────────────────────────────
#   pkgs.claude-code           — the `claude` CLI on home.packages
#   ~/.claude/skills/          — recursive: every skill folder under
#                                ./skills/ becomes available in Claude
#                                Code automatically. Add a new skill =
#                                create folder + rebuild.
#   ~/.claude/settings.json    — generated from the `settings` attrset
#                                below. Schema-validated; see
#                                json.schemastore.org/claude-code-settings.
#                                Includes statusLine, MCP posture,
#                                effort level, dangerous-mode prompt skip.
#
# Future additions follow the same shape:
#   ~/.claude/CLAUDE.md        — user-level CLAUDE.md (cross-project
#                                preferences, persona, working-style)
#   ~/.claude/agents/          — sub-agents
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

let
  # Status line script. Operator's content intact (jq-based parse of the
  # JSON Claude Code pipes in) but PATH injects jq + git so they're
  # guaranteed available — declarative deps beats `nix-shell -p jq` at
  # runtime.
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

  # settings.json content. Single attrset, rendered to JSON below. Each
  # key documented inline so the rationale lives next to the value, not
  # in commit history.
  settings = {
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

    # Default permission mode: auto. Tool calls run without prompting
    # the operator for each one. Pairs with the dangerous-mode prompt
    # skip above — same trust model, applied at the per-call layer.
    permissions.defaultMode = "auto";

    # MCP server posture: per-project opt-in.
    #   * allowManagedMcpServersOnly:    only servers explicitly
    #     allow-listed elsewhere are loadable. Blocks ad-hoc loads.
    #   * enableAllProjectMcpServers:    do NOT auto-trust project-
    #     level .mcp.json files. Each project that wants MCP must
    #     opt in explicitly (via enabledMcpjsonServers in this file
    #     or by accepting the per-project trust prompt once).
    # Together these cap MCP-driven context consumption — large tool
    # surfaces only load when a project actually needs them.
    allowManagedMcpServersOnly = true;
    enableAllProjectMcpServers = false;
    # Auto-trust these specific servers from project .mcp.json files —
    # no per-project trust prompt for the ones we always want. Project
    # .mcp.json declares the actual command + args; this just gates
    # which names are allowed to load.
    enabledMcpjsonServers = [
      "fetch"
      "context7"
    ];

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
  home.packages = [
    pkgs.claude-code # Anthropic CLI; pulls Node closure (~300 MB)
    pkgs.agent-browser # Persistent browser automation for AI agents
    # MCP servers — direct binaries from nixpkgs (no npx-fetch latency,
    # version pinned by flake.lock). Wired into Claude Code via the
    # project-level .mcp.json at the repo root + enabledMcpjsonServers
    # in settings below.
    pkgs.mcp-server-fetch # `fetch` — URL → markdown tool
    pkgs.context7-mcp # `context7` — library docs lookup
  ];

  # Pull each immediate-child directory under `src` into the user's
  # ~/.claude/skills/ as a top-level entry. Claude Code's skill
  # discovery is shallow (expects ~/.claude/skills/<name>/SKILL.md, not
  # nested), so flattening collections from external sources at this
  # boundary keeps every skill discoverable without per-skill
  # boilerplate. recursive = true symlinks at the file level so all
  # entries can coexist under the same parent dir.
  home.file =
    let
      importSkillsDir =
        src:
        lib.mapAttrs' (
          n: _:
          lib.nameValuePair ".claude/skills/${n}" {
            source = "${src}/${n}";
            recursive = true;
          }
        ) (lib.filterAttrs (_: t: t == "directory") (builtins.readDir src));
    in
    lib.mkMerge [
      {
        # In-repo skills (ours): agent-browser, analyse-system,
        # find-skills, wrap-session.
        ".claude/skills" = {
          source = ./skills;
          recursive = true;
        };

        # Generated settings.json — see `settings` attrset above.
        ".claude/settings.json".text = builtins.toJSON settings;
      }

      # Third-party skill collections — flake-input-pinned, mapped one-
      # subdir-per-skill into the flat ~/.claude/skills/.
      (importSkillsDir "${inputs.superpowers}/skills")
      (importSkillsDir "${inputs.caveman}/skills")

      {
        # Single skill from anthropics/skills (the Agent-Skills public
        # repo) — frontend-design only. Add more here as needed; the
        # whole repo is already pulled.
        ".claude/skills/frontend-design" = {
          source = "${inputs.anthropics-skills}/skills/frontend-design";
          recursive = true;
        };
      }
    ];
}
