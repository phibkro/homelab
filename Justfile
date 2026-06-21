#!/usr/bin/env just --justfile
# Common workflows for the nori homelab flake.
#
# Recipes default to running LOCALLY — on whichever host you invoke
# them from. Cross-host execution composes via the `remote` recipe:
#
#   just rebuild                            # build the host you're sitting on
#   just remote workstation rebuild         # rsync working tree to workstation
#                                            # + run `just rebuild` there
#   just remote workstation show-status     # ssh + run `just show-status` there
#   just remote workstation show-logs sshd  # forwarded args work
#
# Implications:
#   - On macOS / Mac dev box: most recipes don't make sense locally
#     (Mac isn't a NixOS host). Use `just remote <host> <recipe>`.
#   - Inside Zed-remote SSH'd into a NixOS host: plain `just rebuild`
#     builds that host — no rsync-back-to-self absurdity.
#
# Install: `brew install just` on macOS; `pkgs.just` (already in
# common/base.nix systemPackages) on NixOS hosts.
#
# ── Recipe-authoring conventions ──────────────────────────────────
#
# 1. **Naming: verb-object.** A recipe name carries both a VERB and
#    an OBJECT (`list-ports`, `show-logs`, `generate-oidc-key`,
#    `test-hypr`). Single-verb names (`rebuild`, `preview`, `boot`,
#    `deploy`) are OK only when the object is "this host's current
#    config" — implicit + universal. Pure nouns (`pending`, `status`,
#    `ports`) are wrong: no verb means unclear what the recipe does.
#
# 2. **The LAST `#` comment line above a recipe is its `just --list`
#    description.** `just --list` shows only that line; multi-line
#    doc-blocks lose all but the last. Write the last line as a
#    self-contained one-liner. Multi-line elaboration goes ABOVE that
#    one-liner, not below.
#
# 3. **Cluster naming.** Test recipes are `test-<thing>`; build flow
#    is `build/preview/rebuild/boot/rollback`; observation is `show-X`,
#    `list-X`, `query-X`; generation is `generate-X`. Match the cluster
#    when adding a new recipe so `just --list | grep ^<verb>-` finds it.
#
# 4. **Co-location.** Recipes coupled to a single concern live with
#    that concern, imported below:
#
#       Concern                              Recipes here          Fragment
#       ─────────                            ──────────────        ────────
#       tests (all layers)                   test-*, e2e-shell     tests/tests.just
#       backup                               backup, check-restic, modules/infra/backup/backup.just
#                                            restore-drill,
#                                            list-snapshots
#       observability                        show-logs, follow,    modules/infra/observability/observability.just
#                                            query-logs
#       networking (lanRoutes)               list-ports            modules/infra/networking/networking.just
#       services layer                       deploy-app            modules/services/services.just
#       secrets / auth                       generate-oidc-key     secrets/auth.just
#
#    Root Justfile carries cross-concern verbs (build/deploy/inspect/
#    push-gate) that aren't coupled to a single module subtree. Adding
#    a new concern with its own surface = drop a `<concern>.just` next
#    to the code + add one `import` line below.

default_host := "workstation"
user         := "nori"
remote_path  := "/tmp/nix-migration"
tailnet      := "saola-matrix.ts.net"

# Every NixOS host in the homelab. Macbook is intentionally NOT here —
# it's a standalone home-manager target, not part of the NixOS flake.
# Used by `rebuild-homelab` to fan rebuild across the set.
homelab_hosts := "workstation pi aurora pavilion"

# rsync flags — BSD openrsync compatible (Mac default rsync is openrsync;
# some GNU flags like --info=stats2 fail silently). See docs/gotchas.md.
rsync_args := "-aH --no-owner --no-group --partial --delete --exclude='.git' --exclude='result' --exclude='inventory-*'"

# ── Imports (co-located concern fragments) ─────────────────────────
import 'tests/tests.just'
import 'modules/infra/backup/backup.just'
import 'modules/infra/observability/observability.just'
import 'modules/infra/networking/networking.just'
import 'modules/services/services.just'
import 'secrets/auth.just'

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

# Ideal for iterating on visual / UX changes (icon themes, Hyprland
# binds, fonts) without polluting the boot menu with throwaway
# generations. Once happy: `just rebuild` to persist as the new default.
#
# Activate the rebuild for the current session only — reverts on reboot.
@preview *args:
    nh os test . -H $(hostname) {{args}}

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

# === push gate ===

# The operator's review surface for the push gate (CLAUDE.md § How to
# operate). Agents must run this (or `git log -p origin/main..HEAD`)
# before any `git push` and get explicit OK.
#
# Show local commits queued for push — full diff + subjects between `main` and `origin/main`.
@show-pending-diff:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! git log --oneline --no-decorate origin/main..HEAD | grep -q .; then
      echo "(none — local is at origin/main)"
      exit 0
    fi
    echo "=== commits queued for push ==="
    git log --oneline --no-decorate origin/main..HEAD
    echo
    echo "=== diff (via delta) ==="
    # delta = syntax-highlighted pager. Auto-narrows on mobile/SSH,
    # side-by-side on wide terminals. --paging=always forces the
    # pager even when piped (so operator can scroll on phone).
    git log -p --reverse origin/main..HEAD | delta --paging=always

# === validate ===

# Run nix flake check (statix + deadnix + nixfmt + eval) locally.
@check:
    nix --extra-experimental-features "nix-command flakes" flake check

# Migration-era one-off checks (path-coherence, multi-line-comments).
# Not part of nix flake check by design — they served the restructure
# phases and have near-nil catch-rate at steady state. Run on demand
# during restructures or when a long-running drift is suspected.
@check-migration:
    bash lint/checks/path-coherence.sh .
    bash lint/checks/multi-line-comments.sh .

# Format all .nix files via the project formatter (nixfmt via nixfmt-tree).
@fmt:
    nix fmt

# Update flake.lock (re-pin inputs). Re-pinning unstable should be deliberate.
@update-flake:
    nix --extra-experimental-features "nix-command flakes" flake update

# === inspect / iterate ===

# Wraps snowfallorg/nix-editor (-i: in-place). Preserves comments +
# style. Doesn't activate — pair with `just preview` to test, `just
# rebuild` to commit, or `git checkout` to revert.
#
# The repo is module-graph not single-file, so the operator picks
# the file — nix-editor is honest about its scope: it won't infer
# where in the import tree a brand-new attribute belongs.
#
# Quoting: shell-quote the whole value-expression so Nix-level quotes
# (for strings) survive. For complex exprs / attrsets, edit by hand.
#
# Usage:
#   just set modules/desktop/stylix.nix stylix.image '"${pkgs.nixos-artwork.wallpapers.dracula}/share/.../image.png"'
#   just set modules/services/blocky.nix services.blocky.enable false
#
# AST-splice a scalar into a `.nix` file, then run the project formatter. Complex exprs: edit by hand.
@set file attr value:
    # nix-editor's -f flag uses nixpkgs-fmt; project uses nixfmt via
    # nixfmt-tree (see flake.nix `formatter.${system} = pkgs.nixfmt-tree;`).
    # Skip -f and run `nix fmt` after to keep style consistent.
    nix run github:snowfallorg/nix-editor -- -i -v '{{value}}' '{{file}}' '{{attr}}'
    nix fmt -- '{{file}}'
    @echo "--- diff ---"
    @git --no-pager diff -- '{{file}}' | head -30
    @echo "--- next: just preview (try) → just rebuild (commit) — or git checkout '{{file}}' to revert ---"

# In-terminal search.nixos.org/options scoped to THIS flake's eval,
# not generic nixpkgs. Pass the dotted attribute path; trailing `.*`
# for everything under a prefix.
#
# Usage:
#   just show-option services.tailscale.enable
#   just show-option stylix.iconTheme.package
#
# Show a NixOS option from THIS flake's eval — type, default, current value, description.
@show-option path:
    @echo "=== type ===" && \
    nix eval --raw .#nixosConfigurations.$(hostname).options.{{path}}.type.description 2>/dev/null || echo "(unknown — wrong path?)"; \
    echo "=== default ===" && \
    nix eval .#nixosConfigurations.$(hostname).options.{{path}}.default 2>/dev/null || echo "(no default)"; \
    echo "=== current ===" && \
    nix eval .#nixosConfigurations.$(hostname).config.{{path}} 2>/dev/null || echo "(unset or computed)"; \
    echo "=== description ===" && \
    nix eval --raw .#nixosConfigurations.$(hostname).options.{{path}}.description 2>/dev/null || echo "(no description)"

# Quick health summary: failed units, disk usage, restic + btrbk timer
# state. Cross-concern (touches systemd + disks + restic), so lives at
# root rather than under any one infra subtree.
@show-status:
    echo "=== failed units ==="
    systemctl --failed --no-pager
    echo
    echo "=== disks ==="
    df -h / /mnt/media /mnt/backup 2>/dev/null || true
    echo
    echo "=== timers (restic + btrbk) ==="
    systemctl list-timers "restic-*" "btrbk-*" --no-pager 2>/dev/null || true

# === ssh — explicit cross-host shell ===

# Drop into another host's shell.
@ssh host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}}

# === doc quality ===

# Reading the whole doc to find the right section is wasteful when
# the `## ` headings already index it. Pair with the editor / Read
# tool to load only the relevant section.
# Usage: just generate-toc gotchas | just generate-toc architecture
#
# Generate a table-of-contents from a doc's `## ` section headings — entry-point into long docs.
@generate-toc doc:
    grep '^## ' docs/{{doc}}.md | sed 's/^## /  /'
