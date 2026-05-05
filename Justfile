#!/usr/bin/env just --justfile
# Common workflows for the nori homelab flake.
#
# Recipes default to running LOCALLY — on whichever host you invoke
# them from. Cross-host execution composes via the `remote` recipe:
#
#   just rebuild                       # build the host you're sitting on
#   just remote nori-station rebuild   # rsync working tree to nori-station
#                                      # + run `just rebuild` there
#   just remote nori-station status    # ssh + run `just status` there
#   just remote nori-station logs sshd # forwarded args work
#
# Implications:
#   - On macOS / Mac dev box: most recipes don't make sense locally
#     (Mac isn't a NixOS host). Use `just remote <host> <recipe>`.
#   - Inside Zed-remote SSH'd into a NixOS host: plain `just rebuild`
#     builds that host — no rsync-back-to-self absurdity.
#
# Install: `brew install just` on macOS; `pkgs.just` (already in
# common/base.nix systemPackages) on NixOS hosts.

default_host := "nori-station"
user         := "nori"
remote_path  := "/tmp/nix-migration"
tailnet      := "saola-matrix.ts.net"

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

# Build but don't activate.
@build *args:
    nh os build . -H $(hostname) {{args}}

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
# uniqueness assertion in modules/lib/lan-route.nix doesn't bite, and
# avoids the cascade-rebind dance when an upstream module's default
# happens to collide. Eval-only; safe to run from any cloned tree.
# Defaults to nori-station because that's where lanRoutes are declared
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

# === backup ===

# Trigger an immediate backup. Usage: just backup <repo>
# Repos: user-data | media-irreplaceable | open-webui | etc.
@backup repo:
    sudo systemctl start restic-backups-{{repo}}.service && journalctl -u restic-backups-{{repo}}.service -f

# Trigger restic check now (weekly cadence is automatic via systemd timer).
@restic-check:
    sudo systemctl start restic-check-weekly.service && journalctl -u restic-check-weekly.service -f

# Trigger the restore drill — verifies backups are *restorable*, not just
# *recorded*. Excludes media-irreplaceable by default; pass `all` to include
# it (multi-hour run). Usage: just restore-drill [all]
@restore-drill mode="quarterly":
    sudo systemctl start restore-drill{{ if mode == "all" { "-all" } else { "" } }}.service && journalctl -u restore-drill{{ if mode == "all" { "-all" } else { "" } }}.service -f

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
