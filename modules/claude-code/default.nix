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
#   ~/.claude/CLAUDE.md        — user-level CLAUDE.md (cross-project
#                                preferences, persona, working-style).
#                                Sourced from ./CLAUDE.md.
#   ~/.claude/agents/          — sub-agents. Recursive symlink from
#                                ./agents/; each <name>.md is a sub-
#                                agent definition.
#   ~/.claude/artifacts/       — long-form reference material Claude
#                                can pull in on demand (essays,
#                                philosophy, frozen context). Recursive
#                                symlink from ./artifacts/.
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

    # Per-skill override map. "user-invocable-only" hides the skill's
    # description from the auto-loaded skills listing (saves ~150-300
    # tokens per session per skill) but keeps the slash-command
    # accessible — `/shadcn-ui`, `/caveman`, etc. still work.
    #
    # Applied to:
    #   * caveman — opt-in compressed-comms mode, not something we want
    #     auto-loaded into every session (still reachable via /caveman)
    #   * frontend-design — heavy token-cost description, only relevant
    #     when actively building UI
    #   * shadcn-ui — same; UI-component-building tool, not a default
    #
    # Anything else stays auto-loaded so the ambient skill list keeps
    # functioning. Add an entry here if a future skill turns out to be
    # too heavy for the auto-discovery slot.
    skillOverrides = {
      caveman = "user-invocable-only";
      frontend-design = "user-invocable-only";
      shadcn-ui = "user-invocable-only";
    };

    # Status line: shown in Claude Code's footer/header. Path is the
    # nix-store hash of the script above; deterministic + reproducible
    # across rebuilds. No symlink in ~/.claude/ needed — Claude reads
    # from the absolute path directly.
    statusLine = {
      type = "command";
      command = "${statuslineScript}";
    };
  };

  # claude-box — OPT-IN sandboxed launcher for the agent itself. `claude` stays
  # the normal unsandboxed command; `claude-box` runs it under bubblewrap with a
  # strict whitelist so a prompt-injection / rogue-tool can't exfiltrate secrets
  # or escape its work. The bwrap FLAGS are the security boundary, not this
  # script — read them.
  #
  # Inside the box the agent CAN: read/write /srv/share/projects, read/write its
  # own ~/.claude state, run its full toolchain (project flakes via `nix
  # develop` over the daemon socket), commit (git identity is bound read-only),
  # and reach the network (the API).
  # It CANNOT: read secrets (~/.ssh, ~/.config/sops age key, ~/.config/gh, and
  # crucially /etc/ssh host keys — sops-nix's master key — and /etc/shadow are
  # all absent), push (no SSH key → run `git push` from a normal shell), mutate
  # the system (no setuid wrappers bound, user namespace blocks sudo), or touch
  # the rest of $HOME (fresh tmpfs; dotfiles absent).
  #
  # Trade-off accepted (operator, 2026-05-30): maximum isolation over
  # convenience — push + system rebuilds happen outside the box, deliberately.
  claudeBox = pkgs.writeShellApplication {
    name = "claude-box";
    runtimeInputs = [ pkgs.bubblewrap ];
    text = ''
      projects="/srv/share/projects"

      # The API credential is the one secret the agent legitimately needs; keep
      # it, clear everything else from the env.
      api_env=()
      if [ -n "''${ANTHROPIC_API_KEY:-}" ]; then
        api_env=(--setenv ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY")
      fi

      exec bwrap \
        --ro-bind /nix/store /nix/store \
        --bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket \
        --ro-bind /run/current-system /run/current-system \
        --ro-bind-try /etc/static /etc/static \
        --ro-bind-try /etc/profiles /etc/profiles \
        --ro-bind-try /etc/nix /etc/nix \
        --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
        --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
        --ro-bind-try /etc/hosts /etc/hosts \
        --ro-bind-try /etc/ssl /etc/ssl \
        --ro-bind-try /etc/passwd /etc/passwd \
        --ro-bind-try /etc/group /etc/group \
        --ro-bind-try /bin /bin \
        --ro-bind-try /usr/bin /usr/bin \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --tmpfs "$HOME" \
        --bind "$projects" "$projects" \
        --bind "$HOME/.claude" "$HOME/.claude" \
        --bind-try "$HOME/.claude.json" "$HOME/.claude.json" \
        --ro-bind-try "$HOME/.config/git" "$HOME/.config/git" \
        --ro-bind-try "$HOME/.nix-profile" "$HOME/.nix-profile" \
        --ro-bind-try "$HOME/.local/state/nix" "$HOME/.local/state/nix" \
        --ro-bind-try "$HOME/.deno" "$HOME/.deno" \
        --chdir "$projects" \
        --clearenv \
        --setenv HOME "$HOME" \
        --setenv USER "''${USER:-nori}" \
        --setenv PATH "$PATH" \
        --setenv TERM "''${TERM:-xterm}" \
        --setenv LANG "''${LANG:-C.UTF-8}" \
        --setenv NIX_REMOTE daemon \
        --setenv SSL_CERT_FILE "''${SSL_CERT_FILE:-''${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}}" \
        "''${api_env[@]}" \
        --unshare-all \
        --share-net \
        --die-with-parent \
        -- claude "$@"
    '';
  };
in
{
  home.packages = [
    pkgs.claude-code # Anthropic CLI; pulls Node closure (~300 MB)
    claudeBox # opt-in `claude-box` — sandboxed agent launcher (see let-block)
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
      # Allowlist a named subset of a third-party skill collection into the
      # flat ~/.claude/skills/. We allowlist rather than import-all so the
      # curated feature-engineering set in ./skills isn't drowned by upstream
      # skills we've replaced (tdd/diagnose/write-a-skill/…) or don't use.
      importSkills =
        src: names:
        lib.listToAttrs (
          map (
            n:
            lib.nameValuePair ".claude/skills/${n}" {
              source = "${src}/${n}";
              recursive = true;
            }
          ) names
        );
    in
    lib.mkMerge [
      {
        # In-repo skills (ours): the curated feature-engineering set —
        # brainstorming, grill-with-docs, tdd, diagnose, wrap-feature,
        # wrap-session, write-a-skill, improve-codebase-architecture — plus
        # agent-browser, analyse-system, find-skills.
        ".claude/skills" = {
          source = ./skills;
          recursive = true;
        };

        # User-level CLAUDE.md — cross-project rules + working-style.
        ".claude/CLAUDE.md".source = ./CLAUDE.md;

        # Sub-agents. Recursive so individual <name>.md files coexist
        # with anything else dropped under ~/.claude/agents/.
        ".claude/agents" = {
          source = ./agents;
          recursive = true;
        };

        # Reference artifacts — long-form material loaded on demand.
        ".claude/artifacts" = {
          source = ./artifacts;
          recursive = true;
        };

        # Generated settings.json — see `settings` attrset above.
        ".claude/settings.json".text = builtins.toJSON settings;
      }

      # Third-party skill collections — flake-input-pinned, mapped one-
      # subdir-per-skill into the flat ~/.claude/skills/.
      # superpowers: only the survivors of the curation (utilities + code
      # review). brainstorming is vendored + adapted in ./skills (repointed
      # to grill-with-docs); test-driven-development/systematic-debugging/
      # writing-skills were replaced by ./skills (tdd/diagnose/write-a-skill);
      # writing-plans/executing-plans/subagent-driven-development/
      # verification-before-completion/finishing-a-development-branch/
      # using-superpowers were dropped.
      (importSkills "${inputs.superpowers}/skills" [
        "dispatching-parallel-agents"
        "receiving-code-review"
        "requesting-code-review"
        "using-git-worktrees"
      ])
      # caveman: keep only the core compressed-comms mode; the -commit/
      # -compress/-help/-review/-stats variants + cavecrew are pruned.
      (importSkills "${inputs.caveman}/skills" [ "caveman" ])

      {
        # Single-skill cherry-picks from larger repos. The whole repo
        # is pulled by the flake input; we only mount the subdir we
        # actually want.
        ".claude/skills/frontend-design" = {
          source = "${inputs.anthropics-skills}/skills/frontend-design";
          recursive = true;
        };
        ".claude/skills/shadcn-ui" = {
          source = "${inputs.shadcn}/skills/shadcn-ui";
          recursive = true;
        };
        ".claude/skills/obsidian-markdown" = {
          source = "${inputs.obsidian-skills}/skills/obsidian-markdown";
          recursive = true;
        };
      }
    ];

  # Shared memory across all /srv/share/projects/* namespaces. Claude Code keys
  # MEMORY.md by the cwd at session-start, so opening `claude` in
  # /srv/share/projects vs. /srv/share/projects/homelab vs. /srv/share/projects/
  # bang-lang gives three disjoint memory pools — the "amnesiac team member"
  # problem. This walks every -srv-share-projects-* namespace Claude Code has
  # already created and symlinks its memory/ to the single canonical at
  # ~/.claude/projects/-srv-share-projects/memory (the orchestration namespace).
  #
  # Reactive — only acts on namespaces that already exist; a fresh project's
  # first session gets a project-local memory dir until the next rebuild
  # symlinks it. Never clobbers a non-empty memory dir (operator merges manually
  # if it ever happens). Idempotent.
  home.activation.claudeSharedMemorySymlinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    canonical="$HOME/.claude/projects/-srv-share-projects/memory"

    if [ -L "$canonical" ]; then
      echo "claude-shared-memory: $canonical is a symlink, expected real dir; skipping" >&2
      exit 0
    fi
    mkdir -p "$canonical"

    for namespace_dir in "$HOME"/.claude/projects/-srv-share-projects-*/; do
      [ -d "$namespace_dir" ] || continue
      memory_link="''${namespace_dir%/}/memory"

      if [ -L "$memory_link" ]; then
        target=$(readlink "$memory_link")
        if [ "$target" != "$canonical" ]; then
          rm "$memory_link"
          ln -s "$canonical" "$memory_link"
        fi
      elif [ -d "$memory_link" ]; then
        if [ -z "$(ls -A "$memory_link" 2>/dev/null)" ]; then
          rmdir "$memory_link"
          ln -s "$canonical" "$memory_link"
        else
          echo "claude-shared-memory: $memory_link has content, not symlinking; merge manually if desired" >&2
        fi
      else
        ln -s "$canonical" "$memory_link"
      fi
    done
  '';
}
