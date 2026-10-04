{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

/**
  Claude Code agent — declarative + reusable. Imported via the PC and agentic
  development profiles on
  every operator-attached PC (workstation). NOT imported by pi:
  no operator agent loop, and the Node closure shouldn't land on pi's
  anti-write SSD.

  Claude-specific static config — ~/.claude/{agents,artifacts}/, the status
  line script, and the managed policy below — is wired in this module.
  ~/.claude/settings.json belongs to the operator: `/config`, `/theme` and
  other in-app commands write it, Nix never touches it, and btrbk and restic
  `user-data` protect it with the rest of /home. Policy that must hold
  regardless (hooks, managed-only MCP keys) is exported as
  `nori.claudeCode.managedSettings`; ./nixos.nix installs it as
  /etc/claude-code/managed-settings.json, which outranks every user file. The
  provider-neutral SOUL is owned by src/users/nori/programs/agent-soul; global
  skills are owned by src/users/nori/programs/agent-skills. Dynamic state
  (per-project memory, per-session todos, ~/.claude.json with OAuth tokens
  + runtime caches) is excluded by design; it mutates per launch and would
  be clobbered on rebuild. Per-project `<project>/.claude/` stays
  per-project.
*/

let
  inherit (pkgs.stdenv.hostPlatform) system;
  agentPackages = inputs.llm-agents.packages.${system};
  paguInput = inputs.pagu;
  tilthInput = inputs.tilth;

  /*
    tilth — MCP server for structural file navigation (tree-sitter
    outlines instead of raw text). Activated per-project via .mcp.json
    + `enableAllProjectMcpServers` in ~/.claude/settings.json. Upstream ships a
    flake; we consume packages.default directly.
    See /srv/share/projects/CLAUDE.md for trigger guidance.

    Override: upstream's checkPhase runs `diff::tests::*` which shell
    out to `git`, but nix's sandbox PATH doesn't include git by
    default. Adding it to nativeBuildInputs lets the tests find the
    binary; without this, all 17 git-shelling tests fail with
    `failed to run git: NotFound`.
  */
  tilth = tilthInput.packages.${system}.default.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.git ];
  });

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

  /*
    Herdr's Claude integration is two artifacts that must agree: a hook script
    on disk, and a `SessionStart` registration that actually invokes it.
    `herdr integration status` reads only the script's version marker, so a
    missing registration still reports "current" (that happened while
    settings.json was a read-only store link and the installer's write
    failed).

    Fix both halves declaratively from the pinned herdr revision, so the script
    and the binary that consumes it can never drift:
      * the script is installed from `inputs.herdr` (home.file, below);
      * the registration is generated here into managed settings, to herdr's
        exact contract (targets.rs `install_claude`): SessionStart only,
        matcher "*", `<script> session`, timeout 10s. The script no-ops unless
        HERDR_ENV=1, HERDR_SOCKET_PATH, and HERDR_PANE_ID are all set, so
        registering it outside Herdr costs one fast exit.
    Do not run `herdr integration install claude`: it would add a second
    registration to the user file, and hooks from every layer run.
    Do not add the PostToolUse/Stop/SubagentStop entries older Herdr versions
    used; v7 explicitly removes them, and SubagentStop could revive an idle
    pane after the turn already ended.
  */
  herdrClaudeHookAsset = "${inputs.herdr}/src/integration/assets/claude/herdr-agent-state.sh";
  herdrClaudeHookPath = "${config.home.homeDirectory}/.claude/hooks/herdr-agent-state.sh";

  /*
    Phone push on every execution-stopping event (nori.agentNotify).
      Stop         — the turn ended.
      Notification — Claude needs permission, or has been waiting on input
                     (covers a pending question).
    Together they cover "an agent halted and needs you". One shared
    entrypoint fans out to ntfy — see src/users/nori/programs/agent-notify/default.nix.
  */
  agentNotifyHooks = lib.optionalAttrs config.nori.agentNotify.enable {
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "${config.nori.agentNotify.command} claude stop";
          }
        ];
      }
    ];
    Notification = [
      {
        hooks = [
          {
            type = "command";
            command = "${config.nori.agentNotify.command} claude notification";
          }
        ];
      }
    ];
  };

  # Herdr is installed only on the Linux workstation; the Intel Mac's stable
  # package set stays isolated, so it gets no pane-state reporting.
  herdrHooks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    SessionStart = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "${pkgs.bash}/bin/bash ${herdrClaudeHookPath} session";
            timeout = 10;
          }
        ];
      }
    ];
  };

  # Disjoint key sets, so `//` is a merge rather than a silent overwrite.
  hooks = agentNotifyHooks // herdrHooks;

  /*
    Managed policy. Managed settings outrank every other layer, arrays such as
    hooks merge with the user's, and some keys are read only from a managed
    source.
      * allowManagedMcpServersOnly: managed-only; ignore MCP allowlists from
        user, project and local settings. No managed allowlist is declared,
        so project `.mcp.json` servers still load.
    Preferences (theme, effort, permission mode, status line, project MCP
    auto-enable) live in the operator's ~/.claude/settings.json.
  */
  managedSettings = {
    allowManagedMcpServersOnly = true;
  }
  // lib.optionalAttrs (hooks != { }) { inherit hooks; };

  /*
    pagu-box — cross-platform sandboxed agent launcher (github:phibkro/
    pagu-box). `--profile=strict` puts $HOME on tmpfs, binds $PWD + the
    agent's state dir RW, blocks secrets (~/.ssh, sops age, gh, host keys),
    blocks system mutation (no setuid binaries, user namespace blocks sudo),
    and blocks `git push` (no SSH key bound — operator pushes from outside).
    claude-box / opencode-box just set cwd and forward args; the strict
    profile + --ro-allow list IS the security boundary.
  */
  pagu-box = paguInput.packages.${system}.pagu-box;

  /*
    `box` — homelab-wrapped pagu-box. Operator-specific policy lives
    here, not upstream: detects "strict + $PWD under the homelab repo"
    and injects --pwd-ro so any sandboxed agent (pi, opencode, Claude)
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

in
{
  imports = [
    inputs.claudex.homeManagerModules.default
    {
      options.nori.claudeCode.managedSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        description = ''
          Claude Code managed policy, installed by ./nixos.nix as
          /etc/claude-code/managed-settings.json.
        '';
      };
    }
  ];

  nori.claudeCode = { inherit managedSettings; };

  programs.claudex.enable = true;

  home.packages = [
    agentPackages.claude-code
    /*
      MCP servers — direct binaries from nixpkgs (no npx-fetch latency,
      version pinned by flake.lock). Wired into Claude Code via the
      project-level .mcp.json at the repo root + `enableAllProjectMcpServers`
      in ~/.claude/settings.json.
    */
    pkgs.mcp-server-fetch # `fetch` — URL → markdown tool
    pkgs.context7-mcp # `context7` — library docs lookup
    /*
      Context-engineering tools — see let-binding for build details +
      /srv/share/projects/CLAUDE.md for trigger guidance.
    */
    tilth # MCP: structural file navigation (tree-sitter outlines)
    stacklit # CLI: per-repo ~250-token static codebase index
  ]
  # pagu-box + the `box` alias both on PATH so nixpkgs-agent's solve.sh
  # can exec the launcher directly.
  ++ [
    pagu-box
    box
  ];

  home.file = lib.mkMerge [
    {
      # ~/.claude/CLAUDE.md is written as a real file by the activation below, not linked here.
      ".claude/agents" = {
        source = ./agents;
        recursive = true;
      };
      ".claude/artifacts" = {
        source = ./artifacts;
        recursive = true;
      };
      # Stable path for the operator's settings.json `statusLine.command`.
      ".claude/statusline.sh".source = statuslineScript;
    }

    # The Herdr control-plane skill is provider-neutral and lives in
    # src/users/nori/programs/agent-skills. Only Claude's lifecycle adapter belongs here.
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      ".claude/hooks/herdr-agent-state.sh" = {
        source = herdrClaudeHookAsset;
        executable = true;
      };
    })
  ];

  /*
    Claude Desktop Cowork sessions skip a ~/.claude/CLAUDE.md that is a
    symlink or hard link (code.claude.com/docs/en/memory, external imports),
    so a store link would silently drop the soul there. Materialize the file
    instead; each activation restores it from agent-soul, which stays the
    single source.
  */
  home.activation.claudeUserInstructions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$HOME/.claude/CLAUDE.md"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 ${../agent-soul/SOUL.md} "$HOME/.claude/CLAUDE.md"
  '';

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
