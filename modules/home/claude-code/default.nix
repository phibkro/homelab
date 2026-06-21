{
  inputs,
  lib,
  pkgs,
  ...
}:

/**
  Claude Code agent — declarative + reusable. Imported via modules/home/pc.nix on
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
  inherit (pkgs.stdenv.hostPlatform) system;

  /*
    claude-code overlaid from nixpkgs-master — channel ships 2.1.148 while
    master ships 2.1.179 (2026-06-21 lock; upstream ~2.1.185). Same
    overlay rationale as zed-editor (modules/home/desktop/apps.nix): the
    26.05 channel is curated + lags, master tracks upstream more closely.
    Revert to plain `pkgs.claude-code` when the channel catches up
    (likely the 26.11 release boundary).

    We must `import` rather than use `legacyPackages` because claude-code
    is unfree, and legacyPackages doesn't inherit allowUnfree from our
    host config (same import-with-config pattern as flake.nix § pkgsUnfree).
  */
  pkgsMaster = import inputs.nixpkgs-master {
    inherit system;
    config.allowUnfree = true;
  };
  claude-code-master = pkgsMaster.claude-code;

  /*
    tilth — MCP server for structural file navigation (tree-sitter
    outlines instead of raw text). Activated per-project via .mcp.json
    + the enabledMcpjsonServers allowlist below. Upstream ships a
    flake; we consume packages.default directly.
    See /srv/share/projects/CLAUDE.md for trigger guidance.

    Override: upstream's checkPhase runs `diff::tests::*` which shell
    out to `git`, but nix's sandbox PATH doesn't include git by
    default. Adding it to nativeBuildInputs lets the tests find the
    binary; without this, all 17 git-shelling tests fail with
    `failed to run git: NotFound`.
  */
  tilth = inputs.tilth.packages.${system}.default.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.git ];
  });

  /*
    rtk — CLI proxy that filters boilerplate from noisy commands before
    they reach the model's context (rtk-ai/rtk). Apache-2.0, single
    Rust binary; no upstream flake.nix, so built here via rustPlatform.
    cargoLock.lockFile points at upstream's Cargo.lock (no cargoHash
    iteration needed).
  */
  rtk = pkgs.rustPlatform.buildRustPackage {
    pname = "rtk";
    version = "unstable-${inputs.rtk-src.shortRev or "dev"}";
    src = inputs.rtk-src;
    cargoLock.lockFile = "${inputs.rtk-src}/Cargo.lock";
    doCheck = false;
    meta = {
      description = "Rust Token Killer — CLI proxy stripping LLM-context boilerplate";
      homepage = "https://github.com/rtk-ai/rtk";
      license = lib.licenses.asl20;
      mainProgram = "rtk";
    };
  };

  /*
    stacklit — generates a ~250-token codebase index (stacklit.json,
    DEPENDENCIES.md, stacklit.html) per repo. MIT, Go binary. The npm
    package is a wrapper that fetches prebuilt binaries (impure), so
    we buildGoModule from source instead. vendorHash bumps with each
    upstream go.sum change.
  */
  stacklit = pkgs.buildGoModule {
    pname = "stacklit";
    version = "0.4.0";
    src = inputs.stacklit-src;
    subPackages = [ "cmd/stacklit" ];
    vendorHash = "sha256-qjQ5P7SLFE1oZvYRGIn97PBPsAsyt/s9PHcGmfvAMHc=";
    meta = {
      description = "Zero-config codebase context for AI agents";
      homepage = "https://github.com/glincker/stacklit";
      license = lib.licenses.mit;
      mainProgram = "stacklit";
    };
  };

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
      /*
        tilth — code-navigation MCP. Allowed by name here; each project
        opts in by declaring it in its .mcp.json:
          { "mcpServers": { "tilth": { "command": "tilth", "args": ["--mcp"] } } }
        Note: tilth uses --mcp as a flag on the root command, not a
        subcommand (see upstream src/main.rs).
      */
      "tilth"
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
    claude-code-master # Anthropic CLI; pulls Node closure (~300 MB). Overlaid from master — see let-binding.
    pkgs.agent-browser # Persistent browser automation for AI agents
    /*
      MCP servers — direct binaries from nixpkgs (no npx-fetch latency,
      version pinned by flake.lock). Wired into Claude Code via the
      project-level .mcp.json at the repo root + enabledMcpjsonServers
      in settings below.
    */
    pkgs.mcp-server-fetch # `fetch` — URL → markdown tool
    pkgs.context7-mcp # `context7` — library docs lookup
    /*
      Context-engineering tools — see let-binding for build details +
      /srv/share/projects/CLAUDE.md for trigger guidance.
    */
    tilth # MCP: structural file navigation (tree-sitter outlines)
    rtk # CLI proxy: noise filter on git/test/build output
    stacklit # CLI: per-repo ~250-token static codebase index
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
      # `subdir` lets the helper reach into nested upstream layouts
      # (Matt Pocock's repo nests by category: skills/engineering/<n>).
      importSkills =
        {
          src,
          subdir ? "",
          names,
        }:
        let
          prefix = if subdir == "" then src else "${src}/${subdir}";
        in
        lib.listToAttrs (
          map (
            n:
            lib.nameValuePair ".claude/skills/${n}" {
              source = "${prefix}/${n}";
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
        to grill-with-docs); writing-plans/executing-plans/subagent-driven-
        development/verification-before-completion/finishing-a-development-
        branch/using-superpowers were dropped. Superpowers' test-driven-
        development + systematic-debugging are superseded by Matt Pocock's
        tdd + diagnosing-bugs below; writing-skills is superseded by
        ./skills/write-a-skill.
      */
      (importSkills {
        src = "${inputs.superpowers}/skills";
        names = [
          "dispatching-parallel-agents"
          "receiving-code-review"
          "requesting-code-review"
          "using-git-worktrees"
        ];
      })
      # caveman: keep only the core compressed-comms mode; the -commit/
      # -compress/-help/-review/-stats variants + cavecrew are pruned.
      (importSkills {
        src = "${inputs.caveman}/skills";
        names = [ "caveman" ];
      })

      /*
        Matt Pocock v1.0.1 engineering + productivity skills. The
        upstream layout nests skills under `skills/<category>/<name>/`;
        we lift the names we want into the flat ~/.claude/skills/ tree
        category-by-category. Excludes:
          • personal/   — operator-personal (obsidian-vault, edit-article)
          • in-progress/ — explicit alpha (writing-shape, review, etc.)
          • misc/migrate-to-shoehorn (TS-lib specific)
          • misc/scaffold-exercises (teaching environments)
        Local ./skills/{improve-codebase-architecture,tdd,diagnose,
        grill-with-docs} were removed when this import landed —
        upstream is canonical.
      */
      (importSkills {
        src = inputs.mattpocock-skills;
        subdir = "skills/engineering";
        names = [
          "ask-matt"
          "codebase-design"
          "diagnosing-bugs"
          "domain-modeling"
          "grill-with-docs"
          "implement"
          "improve-codebase-architecture"
          "prototype"
          "resolving-merge-conflicts"
          "setup-matt-pocock-skills"
          "tdd"
          "to-issues"
          "to-prd"
          "triage"
        ];
      })
      (importSkills {
        src = inputs.mattpocock-skills;
        subdir = "skills/productivity";
        names = [
          "grill-me"
          "grilling"
          "handoff"
          "teach"
          "writing-great-skills"
        ];
      })
      (importSkills {
        src = inputs.mattpocock-skills;
        subdir = "skills/misc";
        names = [
          "git-guardrails-claude-code"
          "setup-pre-commit"
        ];
      })

      {
        ".claude/skills/frontend-design" = {
          source = "${inputs.anthropics-skills}/skills/frontend-design";
          recursive = true;
        };
        ".claude/skills/shadcn-ui" = {
          source = "${inputs.shadcn}/skills/shadcn-ui";
          recursive = true;
        };
        /*
          shadcn/improve — read-only audit + plan-author skill. Pairs
          with the implementation skills (tdd, implement) above by
          producing the spec they execute against.
        */
        ".claude/skills/improve" = {
          source = "${inputs.shadcn-improve}/skills/improve";
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
