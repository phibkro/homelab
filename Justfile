#!/usr/bin/env just --justfile
# Common workflows for the nori homelab flake.
#
# Recipes default to running LOCALLY — on whichever host you invoke
# them from. Cross-host execution composes via the `remote` recipe:
#
#   just rebuild                       # build the host you're sitting on
#   just remote workstation rebuild   # rsync working tree to workstation
#                                      # + run `just rebuild` there
#   just remote workstation status    # ssh + run `just status` there
#   just remote workstation logs sshd # forwarded args work
#
# Implications:
#   - On macOS / Mac dev box: most recipes don't make sense locally
#     (Mac isn't a NixOS host). Use `just remote <host> <recipe>`.
#   - Inside Zed-remote SSH'd into a NixOS host: plain `just rebuild`
#     builds that host — no rsync-back-to-self absurdity.
#
# Install: `brew install just` on macOS; `pkgs.just` (already in
# common/base.nix systemPackages) on NixOS hosts.

default_host := "workstation"
user         := "nori"
remote_path  := "/tmp/nix-migration"
tailnet      := "saola-matrix.ts.net"

# Every NixOS host in the homelab. Macbook is intentionally NOT here —
# it's a standalone home-manager target, not part of the NixOS flake.
# Used by `rebuild-homelab` to fan rebuild across the set.
homelab_hosts := "workstation pi"

# rsync flags — BSD openrsync compatible (Mac default rsync is openrsync;
# some GNU flags like --info=stats2 fail silently). See docs/gotchas.md.
rsync_args := "-aH --no-owner --no-group --partial --delete --exclude='.git' --exclude='result' --exclude='inventory-*'"

# Default recipe — rebuild this host.
default: rebuild

# Show all recipes with their docs.
@list:
    just --list --justfile {{justfile()}}

# === remote — composition primitive ===

# Run a recipe on another host via tailnet SSH.
# Rsyncs the local working tree to {{remote_path}} on <host>, then runs
# `just <recipe>` there. Args after <recipe> forward to the recipe.
# Usage: just remote <host> <recipe> [<args>...]
@remote host +recipe:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote_path}}/
    ssh -t {{user}}@{{host}}.{{tailnet}} 'cd {{remote_path}} && just {{recipe}}'

# === build / deploy (local) ===

# Build + activate this host's configuration from the working tree.
@rebuild *args:
    nh os switch . -H $(hostname) {{args}}

# Sequential rebuild: local first (catches typos fast), then each remote.
# Use after any change that affects multiple hosts — most commonly adding
# a new `nori.lanRoutes.<n>` entry. `just rebuild` only touches whichever
# host you're sitting on; this fans across the homelab set
# ({{homelab_hosts}}) to avoid silent split-brain.
# Build + activate workstation + pi from the working tree.
@rebuild-homelab *args:
    for h in {{homelab_hosts}}; do \
      if [ "$h" = "$(hostname)" ]; then \
        echo "=== local ($h) ==="; \
        just rebuild {{args}}; \
      else \
        echo "=== remote $h ==="; \
        just remote $h rebuild {{args}}; \
      fi; \
    done

# Build but don't activate.
@build *args:
    nh os build . -H $(hostname) {{args}}

# Activate this rebuild for the current session only — no boot entry.
# Reboot reverts to the last `just rebuild`/`switch` generation. Ideal
# for iterating on visual / UX changes (icon themes, Hyprland binds,
# fonts) without polluting the boot menu with throwaway generations.
# Once happy: `just rebuild` to persist as the new default.
@preview *args:
    nh os test . -H $(hostname) {{args}}

# Smoke-test the Hyprland config we just deployed. Three tiers, each
# catching a different class of regression:
#
#   1. Syntax — `hyprctl reload` exit code (catches parse errors).
#   2. Dispatcher — each toggle_special invocation returns "ok"
#      (catches Hyprland-version-bump renames + lua-mode CLI traps
#      like the one that silently broke popup-term 2026-06-07).
#   3. Keypress — wtype synthesises SUPER+ALT+1, checks state
#      changed (catches bind-routing breakage between keystroke
#      and dispatcher — what tier 2 alone can't see).
#
# Each toggle test runs PAIRED (toggle on, toggle off) so the
# operator's session is left exactly as found — tests are
# non-destructive by construction.
#
# Run after `just preview` to validate before `just rebuild`. Or
# anytime, against the live Hyprland. Adds wtype via `nix shell`
# (not installed system-wide).
@test-hypr:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0

    check() {
      local label="$1" expr="$2"
      out=$(hyprctl dispatch "$expr" 2>&1) || { echo "  ✗ $label (hyprctl errored)"; fail=1; return; }
      [[ "$out" == "ok" ]] || { echo "  ✗ $label — got: $out"; fail=1; return; }
      echo "  ✓ $label"
    }

    echo "=== Tier 1 — config parse ==="
    out=$(hyprctl reload 2>&1) && [[ "$out" == "ok" ]] && echo "  ✓ reload" || { echo "  ✗ reload: $out"; fail=1; }

    echo "=== Tier 2 — dispatcher smoke (paired toggles, net effect: zero) ==="
    for tag in browser term music notes comms files; do
      check "toggle special:$tag (on)"  "hl.dsp.workspace.toggle_special({ name = \"$tag\" })"
      check "toggle special:$tag (off)" "hl.dsp.workspace.toggle_special({ name = \"$tag\" })"
    done

    echo "=== Tier 3 — bind registry introspection ==="
    # Pivoted away from live keypress synthesis after research:
    #   * wtype + Hyprland keybinds is known-broken (issue
    #     hyprwm/Hyprland#6647) — virtual keyboard events get filtered
    #     somewhere in the bind matcher pipeline.
    #   * `hl.dsp.send_shortcut(...)` sends to a target window, NOT
    #     through the compositor bind matcher — wrong tool.
    #   * `ydotool` (uinput-level) would work but needs daemon +
    #     /dev/uinput perms + extra setup; not worth the complexity.
    #
    # Static introspection via `hyprctl binds -j` is strictly better:
    # deterministic, layout-independent, runs in <100ms, catches the
    # "I changed my mod combo and forgot to update lua" class of bug
    # that keypress synthesis would also catch — and a few that it
    # wouldn't (binds registered but pointing nowhere).
    #
    # Modmask bits: SHIFT=1, CTRL=4, ALT=8, LOGO/SUPER=64
    # SUPER+ALT = 64+8 = 72.

    binds_json=$(hyprctl binds -j)
    check_bind() {
      local label="$1" modmask="$2" key="$3"
      hit=$(echo "$binds_json" | nix shell nixpkgs#jq -c jq --argjson m "$modmask" --arg k "$key" \
        '[.[] | select(.modmask == $m and .key == $k)] | length')
      if [[ "$hit" -ge 1 ]]; then
        echo "  ✓ $label registered (modmask=$modmask key=$key)"
      else
        echo "  ✗ $label NOT registered (expected modmask=$modmask key=$key)"
        fail=1
      fi
    }
    for tag_n in 1 2 3 4 5 6; do
      check_bind "SUPER+ALT+$tag_n (toggle tag)"        72 "$tag_n"
      check_bind "SUPER+ALT+SHIFT+$tag_n (move to tag)" 73 "$tag_n"
    done
    check_bind "SUPER+RETURN (popup-term)" 64 "RETURN"

    echo
    if [[ "$fail" -eq 0 ]]; then
      echo "=== ALL PASS ==="
    else
      echo "=== FAIL ==="
      exit 1
    fi

# Set a NixOS option to a value via AST edit, no regex. Wraps
# snowfallorg/nix-editor (-i: in-place, -f: format after). Preserves
# comments + style. Doesn't activate — pair with `just preview` to
# test, `just rebuild` to commit, or `git checkout` to revert.
#
# The repo is module-graph not single-file, so the operator picks
# the file (nix-editor is honest about its scope: it won't infer
# where in the import tree a brand-new attribute belongs).
#
# Usage:
#   just set modules/desktop/stylix.nix stylix.image '"${pkgs.nixos-artwork.wallpapers.dracula}/share/.../image.png"'
#   just set modules/services/blocky.nix services.blocky.enable false
#
# Quoting matters: shell-quote the whole value-expression so that
# Nix-level quotes (for strings) survive. For complex expressions or
# attribute set values, edit by hand — nix-editor's sweet spot is
# scalar assignments.
@set file attr value:
    # nix-editor's -f flag uses nixpkgs-fmt; project uses nixfmt (see
    # flake.nix `formatter.${system} = pkgs.nixfmt;`). Skip -f and run
    # project's nixfmt after to keep style consistent.
    nix run github:snowfallorg/nix-editor -- -i -v '{{value}}' '{{file}}' '{{attr}}'
    nix fmt -- '{{file}}'
    @echo "--- diff ---"
    @git --no-pager diff -- '{{file}}' | head -30
    @echo "--- next: just preview (try) → just rebuild (commit) — or git checkout '{{file}}' to revert ---"

# Inspect a NixOS option from THIS flake's evaluated config — type,
# default, current value, description. The in-terminal version of
# search.nixos.org/options scoped to your actual config, not generic
# nixpkgs. Usage:
#   just option services.tailscale.enable
#   just option stylix.iconTheme.package
# Pass the dotted attribute path; trailing `.*` for everything under
# a prefix.
@option path:
    @echo "=== type ===" && \
    nix eval --raw .#nixosConfigurations.$(hostname).options.{{path}}.type.description 2>/dev/null || echo "(unknown — wrong path?)"; \
    echo "=== default ===" && \
    nix eval .#nixosConfigurations.$(hostname).options.{{path}}.default 2>/dev/null || echo "(no default)"; \
    echo "=== current ===" && \
    nix eval .#nixosConfigurations.$(hostname).config.{{path}} 2>/dev/null || echo "(unset or computed)"; \
    echo "=== description ===" && \
    nix eval --raw .#nixosConfigurations.$(hostname).options.{{path}}.description 2>/dev/null || echo "(no description)"

# Activate at next boot only (for kernel/initrd changes).
@boot *args:
    nh os boot . -H $(hostname) {{args}}

# Roll back to the previous generation.
@rollback:
    sudo nixos-rebuild switch --rollback

# Build + activate from origin's main branch (no working-tree state).
# Useful for "deploy what's on github" without touching the local tree.
@deploy:
    nh os switch github:phibkro/homelab -H $(hostname)

# === validate ===

# Run nix flake check (statix + deadnix + nixfmt + eval) locally.
@check:
    nix --extra-experimental-features "nix-command flakes" flake check

# Format all .nix files via nixfmt.
@fmt:
    nix-shell -p nixfmt-rfc-style --command "find . -name '*.nix' -not -path './result*' -exec nixfmt {} +"

# Update flake.lock (re-pin inputs). Re-pinning unstable should be deliberate.
@update:
    nix --extra-experimental-features "nix-command flakes" flake update

# === observe (local) ===

# Show the *.nori.lan port allocation table sorted by port. Useful before
# adding a new service — confirms what's taken so the eval-time port-
# uniqueness assertion in modules/effects/lan-route.nix doesn't bite, and
# avoids the cascade-rebind dance when an upstream module's default
# happens to collide. Eval-only; safe to run from any cloned tree.
# Defaults to workstation because that's where lanRoutes are declared
# (Pi's lanRoutes are gated on Caddy presence and so always empty).
@ports host=default_host:
    nix --extra-experimental-features "nix-command flakes" eval --raw \
        .#nixosConfigurations.{{host}}.config.nori.lanRoutes \
        --apply 'lr: let pairs = builtins.attrValues (builtins.mapAttrs (n: v: { name = n; port = v.port; }) lr); sorted = builtins.sort (a: b: a.port < b.port) pairs; in (builtins.concatStringsSep "\n" (map (e: "  ${toString e.port}\t${e.name}") sorted)) + "\n"'

# Quick health summary: failed units, disk usage, restic + btrbk timer state.
@status:
    echo "=== failed units ==="
    systemctl --failed --no-pager
    echo
    echo "=== disks ==="
    df -h / /mnt/media /mnt/backup 2>/dev/null || true
    echo
    echo "=== timers (restic + btrbk) ==="
    systemctl list-timers "restic-*" "btrbk-*" --no-pager 2>/dev/null || true

# Tail recent journal lines for a unit. Usage: just logs <unit>
@logs unit:
    sudo journalctl -u {{unit}} -n 50 --no-pager

# Live-tail a unit. Usage: just follow <unit>
@follow unit:
    sudo journalctl -u {{unit}} -f

# Query the central VictoriaLogs index via LogsQL. Usage:
#   just query-logs 'unit:ollama.service priority:<=3 | head 20'
#   just query-logs 'level:error | _time:1h | stats by (unit) count()'
# Pi tailnet IP is hardcoded — it's stable and avoids an extra nix-eval
# per invocation. See .claude/skills/query-logs/SKILL.md for syntax.
@query-logs query:
    curl -sG "http://100.100.71.3:9428/select/logsql/query" \
        --data-urlencode 'query={{query}}' \
      | (command -v jq >/dev/null && jq . || cat)

# === backup ===

# Trigger an immediate backup. Usage: just backup <repo>
# Repos: user-data | media-irreplaceable | open-webui | etc.
@backup repo:
    sudo systemctl start restic-backups-{{repo}}.service && journalctl -u restic-backups-{{repo}}.service -f

# Trigger restic check now (weekly cadence is automatic via systemd timer).
@restic-check:
    sudo systemctl start restic-check-weekly.service && journalctl -u restic-check-weekly.service -f

# Trigger a restore drill — verifies backups are *restorable*, not just
# *recorded*. Three tiers split by cost + cadence; `services` is cheap and
# fast, `user-data` is the heavy one, `all` includes media-irreplaceable
# (multi-hour). Usage: just restore-drill [services|user-data|all]
@restore-drill tier="services":
    sudo systemctl start restore-drill-{{tier}}.service && journalctl -u restore-drill-{{tier}}.service -f

# List restic snapshots for a repo. Usage: just snapshots <repo>
@snapshots repo:
    sudo /run/current-system/sw/bin/restic -r /mnt/backup/{{repo}} --password-file /run/secrets/restic-password snapshots

# === auth ===

# Generate raw + PBKDF2 hash for a new lan-route OIDC client and print
# two paste-ready YAML lines for sops. Output is sensitive — copy both
# lines, paste into `sops secrets/secrets.yaml`, then `just rebuild`.
# Usage: just oidc-key <name>
@oidc-key name:
    nix shell nixpkgs#openssl nixpkgs#authelia --command bash scripts/oidc-key.sh {{name}}

# === ssh — explicit cross-host shell ===

# Drop into another host's shell.
@ssh host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}}

# === doc quality ===

# Show a doc's section headings — T2 entry point into the T3 contents.
# Reading the whole doc to find the right section is wasteful when the
# `## ` headings already index it. Pair with the editor / Read tool to
# load only the relevant section.
# Usage: just toc gotchas | just toc architecture | just toc CONVENTIONS
@toc doc:
    grep '^## ' docs/{{doc}}.md | sed 's/^## /  /'

# Build + publish a self-deployed app's static artifact (or refresh a
# running one). Each app's modules/services/<name>.nix declares a
# `<name>-build.service` oneshot — this recipe just kicks it. Operator
# triggers explicitly so nixos-rebuild stays fast (no npm-install on
# every rebuild). Logs stream live, exit code matches the unit's.
# Usage: just deploy-app filmder
deploy-app name:
    sudo systemctl start --wait {{name}}-build.service
    @echo ""
    @echo "[deploy-app {{name}}] Last 20 log lines:"
    @journalctl -u {{name}}-build.service --no-pager -n 20

# Print the prompt for dispatching a fresh agent through the onboarding test.
# The test (docs/agent-onboarding-test.md) measures whether session wrap-ups
# left enough context for a fresh agent to perform — closes the otherwise-open
# loop on the "On every structural change" / "On session end" rubrics.
# Run after major refactors or when the user pushes back on doc clarity.
@agent-onboarding-test:
    @echo "Onboarding test — dispatch a fresh subagent (or fresh Claude session) with:"
    @echo ""
    @echo "  You are a fresh agent with zero prior context on this homelab project."
    @echo "  Read CLAUDE.md first to orient. Then for each numbered question in"
    @echo "  docs/agent-onboarding-test.md, give a terse answer (~3 bullets)"
    @echo "  using only files reachable from CLAUDE.md's routing table. Cite the"
    @echo "  source file. Don't read the 'Expected (shape)' sections until AFTER"
    @echo "  you've answered — those are grading rubrics, not hints."
    @echo ""
    @echo "Then compare answers to 'Expected (shape)' in each question. Failures:"
    @echo "  - knowledge gap (info missing)"
    @echo "  - routing gap (info exists but unreachable from CLAUDE.md)"
    @echo "  - foregrounding gap (reachable but not where the agent looks first)"
    @echo ""
    @echo "Fix the gap and re-run."
