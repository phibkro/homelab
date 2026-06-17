{
  inputs,
  lib,
  pkgs,
  ...
}:

/**
  Claude Code agent — declarative + reusable. Imported via home/pc.nix on
  every operator-attached PC (workstation + macbook). NOT imported by pi:
  no operator agent loop, and the Node closure shouldn't land on pi's
  anti-write SSD.

  Static config only — settings.json, CLAUDE.md, ~/.claude/{skills,agents,
  artifacts}/ — wired in the home.file block below. Dynamic state
  (per-project memory, per-session todos, ~/.claude.json with OAuth tokens
  + runtime caches) is excluded by design; it mutates per launch and would
  be clobbered on rebuild. Per-project `<project>/.claude/` stays
  per-project.
*/

let
  /*
    Status line script. Operator's content intact (jq-based parse of the
    JSON Claude Code pipes in) but PATH injects jq + git so they're
    guaranteed available — declarative deps beats `nix-shell -p jq` at
    runtime.
  */
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

    if [ -n "$remaining" ]; then
        status="$status | Context: ''${remaining}%"
    fi

    echo "$status"
  '';

  settings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";

    theme = "auto";

    /*
      Default thinking depth. "high" gives Opus more headroom for
      deeper structural reasoning by default; flip to "medium" if
      latency starts to bite.
    */
    effortLevel = "high";

    # Trusted dev loop — skip the launch-time warning AND don't prompt
    # per tool call. Same trust model at two layers.
    skipDangerousModePermissionPrompt = true;
    permissions.defaultMode = "auto";

    /*
      MCP server posture: per-project opt-in.
        * allowManagedMcpServersOnly:    only servers explicitly
          allow-listed elsewhere are loadable. Blocks ad-hoc loads.
        * enableAllProjectMcpServers:    do NOT auto-trust project-
          level .mcp.json files. Each project that wants MCP must
          opt in explicitly (via enabledMcpjsonServers in this file
          or by accepting the per-project trust prompt once).
      Together these cap MCP-driven context consumption — large tool
      surfaces only load when a project actually needs them.
    */
    allowManagedMcpServersOnly = true;
    enableAllProjectMcpServers = false;
    /*
      Auto-trust these specific servers from project .mcp.json files —
      no per-project trust prompt for the ones we always want. Project
      .mcp.json declares the actual command + args; this just gates
      which names are allowed to load.
    */
    enabledMcpjsonServers = [
      "fetch"
      "context7"
    ];

    /*
      "user-invocable-only" hides the description from auto-loaded
      skills (saves ~150-300 tokens/session per skill) but keeps
      `/<name>` reachable. Applied to skills too heavy for the
      auto-discovery slot — opt-in modes (caveman) and UI tools
      (frontend-design, shadcn-ui).
    */
    skillOverrides = {
      caveman = "user-invocable-only";
      frontend-design = "user-invocable-only";
      shadcn-ui = "user-invocable-only";
    };

    statusLine = {
      type = "command";
      command = "${statuslineScript}";
    };
  };

  /*
    pagu-box — cross-platform sandboxed agent launcher (github:phibkro/
    pagu-box). `--profile=strict` puts $HOME on tmpfs, binds $PWD + the
    agent's state dir RW, blocks secrets (~/.ssh, sops age, gh, host keys),
    blocks system mutation (no setuid binaries, user namespace blocks sudo),
    and blocks `git push` (no SSH key bound — operator pushes from outside).
    claude-box / opencode-box just set cwd and forward args; the strict
    profile + --ro-allow list IS the security boundary.
  */
  pagu-box = inputs.pagu-box.packages.${pkgs.stdenv.hostPlatform.system}.default;

  /*
    `box` — homelab-wrapped pagu-box. Operator-specific policy lives
    here, not upstream: detects "strict + $PWD under the homelab repo"
    and injects --pwd-ro so any sandboxed agent (hermes, pi, opencode)
    reads homelab config but can't edit it. Operator's own claude-code
    runs outside the sandbox and is unaffected.
  */
  box = pkgs.writeShellApplication {
    name = "box";
    runtimeInputs = [ pagu-box ];
    text = ''
      # multi-line: ok
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

      # multi-line: ok
      # box-launched agents always get read-only journal access. Debugging the
      # host (services, boot history, OOMs) is the common case for box invocations
      # and the alternative is the operator pasting !-prefixed journalctl into
      # the agent's session. Risk model: logs may contain accidentally-logged
      # tokens — mitigation lives at the source (don't log them), not here.
      extra=( --journal )
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

  /*
    pi — github:badlogic/pi-mono coding-agent CLI. Installed via npm at
    ~/.local/lib/node_modules/@earendil-works/pi-coding-agent. The wrapper
    puts `pi` on the system PATH (so it's reachable from inside box) and
    uses nixpkgs nodejs to run it, so the user doesn't need a separately
    installed node.
  */
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

  # opencode-box — same shape as claudeBox; bound state dir is
  # ~/.config/opencode.
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
  home.packages = [
    pkgs.claude-code # Anthropic CLI; pulls Node closure (~300 MB)
    pkgs.agent-browser # Persistent browser automation for AI agents
    /*
      MCP servers — direct binaries from nixpkgs (no npx-fetch latency,
      version pinned by flake.lock). Wired into Claude Code via the
      project-level .mcp.json at the repo root + enabledMcpjsonServers
      in settings below.
    */
    pkgs.mcp-server-fetch # `fetch` — URL → markdown tool
    pkgs.context7-mcp # `context7` — library docs lookup
  ]
  # opencode lacks x86_64-darwin support in nixpkgs 26.05 (aarch64-darwin
  # only). Skip on Intel Mac.
  ++ lib.optional (pkgs.stdenv.hostPlatform.system != "x86_64-darwin") pkgs.opencode
  # pagu-box + the `box` alias both on PATH so nixpkgs-agent's solve.sh
  # can exec the launcher directly.
  ++ [
    pagu-box
    box
    piAgent
  ]
  # claude-box / opencode-box are bwrap-based; Linux-only.
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    claudeBox
    opencodeBox
  ];

  /*
    Claude Code skill discovery is shallow (~/.claude/skills/<name>/
    SKILL.md, not nested), so external collections get flattened one-
    subdir-per-skill into the flat tree. recursive=true symlinks at the
    file level so multiple sources can coexist under the same parent dir.
  */
  home.file =
    let
      # Allowlist rather than import-all so the curated ./skills set
      # isn't drowned by upstream skills we've replaced or don't use.
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
        ".claude/skills" = {
          source = ./skills;
          recursive = true;
        };
        ".claude/CLAUDE.md".source = ./CLAUDE.md;
        ".claude/agents" = {
          source = ./agents;
          recursive = true;
        };
        ".claude/artifacts" = {
          source = ./artifacts;
          recursive = true;
        };
        ".claude/settings.json".text = builtins.toJSON settings;
      }

      /*
        Third-party skill collections — flake-input-pinned, mapped one-
        subdir-per-skill into the flat ~/.claude/skills/.
        superpowers: only the survivors of the curation (utilities + code
        review). brainstorming is vendored + adapted in ./skills (repointed
        to grill-with-docs); test-driven-development/systematic-debugging/
        writing-skills were replaced by ./skills (tdd/diagnose/write-a-skill);
        writing-plans/executing-plans/subagent-driven-development/
        verification-before-completion/finishing-a-development-branch/
        using-superpowers were dropped.
      */
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

  /*
    Claude Code Remote Control — server-mode session so the Claude
    mobile app + claude.ai/code can spawn fresh sessions against this
    workstation. Outbound HTTPS only (no inbound ports); chat + tool
    results flow through Anthropic's relay, not tailnet — the trade
    for zero infra and off-tailnet access.

    Runs INSIDE claude-box: a prompt-injected remote session inherits
    the same blast-radius cap as a local one (no ~/.ssh, no sops keys,
    no system mutate, no `git push`). Per-call permission policy comes
    from settings.json `permissions.defaultMode = "auto"`.

    Do NOT pass --dangerously-skip-permissions to `remote-control`: the
    subcommand rejects that flag with "Unknown argument" and the unit
    spins in a restart loop. The flag is interactive-`claude`-only.

    First-time setup (manual one-shot, service won't start otherwise):
      1. `claude` in a normal shell
      2. `/login` + complete OAuth (API-key auth NOT supported here)
      3. `systemctl --user enable --now claude-remote-control`
    Inspect: `systemctl --user status claude-remote-control` /
             `journalctl --user -fu claude-remote-control`. Session
             name `workstation-*` appears in startup logs + claude.ai/code.

    Linux-only: claudeBox is bwrap-based, systemd user services don't
    exist on darwin. Mac equivalent (launchd) not wired yet.
  */
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
        /*
          Cap restart loop so a chronic outage / bad creds don't burn CPU
          in a tight retry spin — five tries in five minutes is enough to
          surface the failure via `systemctl status`.
        */
        StartLimitIntervalSec = "300";
        StartLimitBurst = "5";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  /*
    Shared memory across /srv/share/projects/* namespaces. Claude Code
    keys MEMORY.md by cwd at session-start, so launching in /srv/share/
    projects vs. .../homelab vs. .../bang-lang gives three disjoint
    memory pools ("amnesiac team member"). Walks every existing
    -srv-share-projects-* namespace and symlinks its memory/ to the
    single canonical at ~/.claude/projects/-srv-share-projects/memory.
    Reactive: a fresh project's first session gets a project-local
    memory dir until the next rebuild. Never clobbers a non-empty dir
    (operator merges manually).
  */
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
