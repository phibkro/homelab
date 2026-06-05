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

  # claude-box / opencode-box — thin aliases over `pagu-box` (the
  # cross-platform sandboxed launcher; see github:phibkro/pagu-box).
  # Both wrap their respective agent under pagu-box's `strict` profile:
  # $HOME is tmpfs, only $PWD + ~/.claude (config + state) bound RW,
  # and a workstation-specific RO set is added for git config / nix
  # profile / deno cache.
  #
  # Inside the box the agent CAN: read/write /srv/share/projects, read/
  # write its own ~/.claude state (or ~/.config/opencode for opencode),
  # run its full toolchain (project flakes via `nix develop` over the
  # daemon socket), commit (git identity is RO-bound), and reach the
  # network (the API).
  # It CANNOT: read secrets (~/.ssh, ~/.config/sops age key, ~/.config/gh,
  # /etc/ssh host keys, /etc/shadow), push (no SSH key — run `git push`
  # from a normal shell), mutate the system (no setuid wrappers bound,
  # user namespace blocks sudo), or touch the rest of $HOME.
  #
  # The strict-profile + --ro-allow list IS the security boundary; the
  # alias just sets cwd and forwards args. Before-state (inline ~50-line
  # bwrap script + opencode's landrun layer) consolidated 2026-06-05 —
  # landrun dropped, the bwrap shape now lives in pagu-box itself.
  pagu-box = inputs.pagu-box.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Short alias for muscle memory — `box <cmd>` is much less typing than
  # `pagu-box <cmd>` for the launcher that should land in every shell
  # invocation. Repo + nix package keep the longer name for clarity;
  # the CLI is `box`.
  # `box` is the operator-deployed wrapper around upstream pagu-box. It's
  # where operator-specific policy goes — pagu-box itself is general (a
  # `--pwd-ro` primitive); the homelab-tree-is-read-only rule belongs HERE,
  # not in upstream. The wrapper detects "strict + $PWD under the homelab
  # repo" and injects --pwd-ro so any sandboxed agent (hermes, pi, opencode
  # …) reads homelab config but can't edit it. Operator's own claude-code
  # runs OUTSIDE the sandbox and is unaffected.
  box = pkgs.writeShellApplication {
    name = "box";
    runtimeInputs = [ pagu-box ];
    text = ''
      # Inspect args for --profile=strict (or `--profile strict`) without
      # consuming them. If yes AND $PWD is under the homelab repo, prepend
      # --pwd-ro. Anything else passes through untouched.
      homelab_prefix="/srv/share/projects/homelab"
      profile=""
      args=("$@")
      i=0
      while [ $i -lt ''${#args[@]} ]; do
        case "''${args[$i]}" in
          --profile=*) profile="''${args[$i]#--profile=}" ;;
          --profile)
            i=$((i + 1))
            profile="''${args[$i]:-}"
            ;;
        esac
        i=$((i + 1))
      done

      extra=()
      case "$PWD" in
        "$homelab_prefix"|"$homelab_prefix"/*)
          if [ "$profile" = "strict" ]; then
            echo "box: \$PWD is under $homelab_prefix — injecting --pwd-ro." >&2
            echo "     Homelab config edits go through operator review (claude-code)." >&2
            extra+=( --pwd-ro )
          fi
          ;;
      esac

      exec pagu-box "''${extra[@]}" "$@"
    '';
  };

  # pi — github:badlogic/pi-mono coding-agent CLI. Installed via npm at
  # ~/.local/lib/node_modules/@earendil-works/pi-coding-agent. The wrapper
  # puts `pi` on the system PATH (so it's reachable from inside box) and
  # uses nixpkgs nodejs to run it, so the user doesn't need a separately
  # installed node.
  piAgent = pkgs.writeShellApplication {
    name = "pi";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec node /home/nori/.local/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js "$@"
    '';
  };

  claudeBox = pkgs.writeShellApplication {
    name = "claude-box";
    runtimeInputs = [
      pagu-box
      pkgs.claude-code
    ];
    text = ''
      cd /srv/share/projects
      exec pagu-box --profile=strict \
        --ro-allow "$HOME/.config/git" \
        --ro-allow "$HOME/.nix-profile" \
        --ro-allow "$HOME/.local/state/nix" \
        --ro-allow "$HOME/.deno" \
        -- claude "$@"
    '';
  };

  # opencode-box — pagu-box wrapping opencode under the strict profile.
  # Same shape as claudeBox but bound state dir is ~/.config/opencode.
  # Pre-consolidation this also layered landrun (Landlock LSM) inside
  # bwrap for defense-in-depth; dropped 2026-06-05 — bwrap alone is the
  # security boundary, the second wall added complexity disproportionate
  # to the marginal extra hardening.
  #
  # Talking to local Ollama from opencode — TL;DR config:
  #   ~/.config/opencode/config.json. Provider block:
  #     {
  #       "providers": {
  #         "ollama-local": {
  #           "npm": "@ai-sdk/openai-compatible",
  #           "options": { "baseURL": "http://127.0.0.1:11434/v1" },
  #           "models": { "gemma4:12b-mxfp8": {} }
  #         }
  #       }
  #     }
  #   See https://opencode.ai/docs/providers/ for the current schema.
  opencodeBox = pkgs.writeShellApplication {
    name = "opencode-box";
    runtimeInputs = [
      pagu-box
      pkgs.opencode
    ];
    text = ''
      cd /srv/share/projects
      mkdir -p "$HOME/.config/opencode"
      exec pagu-box --profile=strict \
        --allow "$HOME/.config/opencode" \
        --ro-allow "$HOME/.config/git" \
        --ro-allow "$HOME/.nix-profile" \
        --ro-allow "$HOME/.local/state/nix" \
        --env OPENROUTER_API_KEY \
        --env GROQ_API_KEY \
        --env OPENCODE_API_KEY \
        -- opencode "$@"
    '';
  };
in
{
  home.packages =
    [
      pkgs.claude-code # Anthropic CLI; pulls Node closure (~300 MB)
      pkgs.agent-browser # Persistent browser automation for AI agents
      # MCP servers — direct binaries from nixpkgs (no npx-fetch latency,
      # version pinned by flake.lock). Wired into Claude Code via the
      # project-level .mcp.json at the repo root + enabledMcpjsonServers
      # in settings below.
      pkgs.mcp-server-fetch # `fetch` — URL → markdown tool
      pkgs.context7-mcp # `context7` — library docs lookup
    ]
    # opencode lacks x86_64-darwin support in nixpkgs 26.05 (aarch64-darwin
    # only). Skip on Intel Mac.
    ++ lib.optional (pkgs.stdenv.hostPlatform.system != "x86_64-darwin") pkgs.opencode
    # pagu-box itself on PATH (was previously only reachable via the
    # claude-box / opencode-box runtimeInputs). Lets nixpkgs-agent's
    # solve.sh exec it directly. Both names — the canonical `pagu-box`
    # and the short alias `box` — go on PATH.
    ++ [ pagu-box box piAgent ]
    # Hermes Agent (NousResearch) lives in its own module — see
    # ../hermes/default.nix. Imported alongside this one from pc.nix.
    # claudeBox / opencodeBox are bwrap (+ landrun) wrappers — Linux-only.
    # Both delegate to pagu-box internally now.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      claudeBox
      opencodeBox
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
  # Claude Code Remote Control — register a long-running SERVER-MODE session
  # so the Claude mobile app + claude.ai/code can spawn fresh sessions on
  # demand against this workstation. The local process polls Anthropic's
  # API for work over outbound HTTPS only — NO inbound ports open here.
  # Code/repos never leave the machine; only chat + tool results flow
  # through an encrypted bridge (their relay, not tailnet — the trade for
  # zero infra and off-tailnet access).
  #
  # Runs INSIDE claude-box, so a prompt-injected remote session inherits
  # the same blast-radius cap as a local one (no ~/.ssh, no sops keys, no
  # system mutate, no `git push`). Per-session permission policy comes
  # from settings.json `permissions.defaultMode = "auto"` — that's the
  # load-bearing setting. Earlier draft passed --dangerously-skip-permissions
  # here; `claude remote-control` (server mode) rejects that flag with
  # "Unknown argument: --dangerously-skip-permissions" and the unit went
  # into a permanent restart loop. The flag only applies to interactive
  # `claude`, not the server-mode subcommand.
  #
  # Multi-session via server mode: each spawned session shares cwd
  # (/srv/share/projects, can cd into projects), gets an auto-generated
  # name like `workstation-graceful-unicorn`.
  #
  # First-time setup (one-shot, manual — service won't run cleanly otherwise):
  #   1. `claude` in a normal interactive shell
  #   2. `/login` and complete the claude.ai OAuth flow
  #      (Remote Control requires OAuth; API key auth NOT supported)
  #   3. `systemctl --user enable --now claude-remote-control`
  #
  # Inspect:    `systemctl --user status claude-remote-control`
  # Logs:       `journalctl --user -fu claude-remote-control`
  # Session URL/QR: in startup logs, plus claude.ai/code session list
  #             (look for `workstation-*` entries).
  # Push notifications: enable inside any spawned session via `/config`
  #             → "Push when Claude decides" (needs v2.1.110+).
  #
  # Limits (per Anthropic docs as of 2026-06): >10 min unreachable relay =
  # process exits cleanly; systemd restarts. Each server-mode process
  # supports many concurrent spawned sessions (default cap 32). Ultraplan
  # disconnects Remote Control.
  # Linux-only: systemd user services don't exist on darwin, and ExecStart
  # references claudeBox which is bwrap-based. The mac equivalent (launchd)
  # for remote-control isn't wired up yet — when it is, mirror this block
  # under `launchd.user.agents` gated on isDarwin.
  systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    claude-remote-control = {
      Unit = {
        Description = "Claude Code Remote Control (multi-session bridge for phone/web)";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "exec";
        WorkingDirectory = "/srv/share/projects";
        ExecStart = "${claudeBox}/bin/claude-box remote-control --remote-control-session-name-prefix workstation --verbose";
        Restart = "on-failure";
        RestartSec = "10s";
        # Cap restart loop so a chronic outage / bad creds don't burn CPU
        # in a tight retry spin — five tries in five minutes is enough to
        # surface the failure via `systemctl status`.
        StartLimitIntervalSec = "300";
        StartLimitBurst = "5";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

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
