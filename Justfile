#!/usr/bin/env just --justfile

default_host := "workstation"
user         := "nori"
remote_path  := "/tmp/nix-migration"
tailnet      := "saola-matrix.ts.net"

# Used by `rebuild-homelab` to keep the one-host flow explicit.
homelab_hosts := "workstation"

# some GNU flags like --info=stats2 fail silently). See docs/gotchas.md.
rsync_args := "-aH --no-owner --no-group --partial --delete --exclude='.git' --exclude='.worktrees' --exclude='.devenv' --exclude='node_modules' --exclude='result' --exclude='inventory-*'"

# ── Imports (co-located concern fragments) ─────────────────────────
import 'tests/tests.just'
import 'tests/backup.just'
import 'tests/observability.just'
import 'tests/networking.just'
import 'tests/services.just'
mod pi 'infra/pi/pi.just'

# Default recipe is read-only help.
default: list

# Show all recipes with their docs.
@list:
    just --list --justfile {{justfile()}}


# Usage: just remote <host> <recipe> [<args>...]
@remote host +recipe:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote_path}}/
    ssh -t {{user}}@{{host}}.{{tailnet}} 'cd {{remote_path}} && just {{recipe}}'


# Derive affected build targets from inventory and changes since a Git ref.
@plan-deploy base="origin/main":
    nix run .#deployment-plan -- --changed-since {{base}}

# Build + activate this host's configuration from the working tree.
@rebuild *args:
    nh os switch . -H $(hostname) {{args}}

# Open public maintenance, rebuild locally, and close only after success.
@rebuild-maintained *args:
    secretspec run --profile workstation --scope public-status -- nix run .#statusctl -- maintained --title "Rebuild $(hostname)" -- just rebuild {{args}}

# Build + activate workstation from the working tree.
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

# Usage: just push <host> [extra nixos-rebuild args]
@push host *args:
    nixos-rebuild switch \
      --flake .#{{host}} \
      --target-host {{user}}@{{host}}.{{tailnet}} \
      --sudo \
      {{args}}

# Open public maintenance, push a NixOS host, and close only after success.
@push-maintained host *args:
    secretspec run --profile workstation --scope public-status -- nix run .#statusctl -- maintained --title "Deploy {{host}}" -- just push {{host}} {{args}}

# Open public maintenance, converge Pi, and close only after success.
@pi-deploy-maintained:
    secretspec run --profile workstation --scope public-status -- nix run .#statusctl -- maintained --title "Deploy pi" -- just pi::deploy

# Build but don't activate.
@build *args:
    nh os build . -H $(hostname) {{args}}

# Activate the rebuild for the current session only — reverts on reboot.
@activate-test *args:
    nh os test . -H $(hostname) {{args}}

# Activate at next boot only (for kernel/initrd changes).
@boot *args:
    nh os boot . -H $(hostname) {{args}}

# Roll back to the previous generation.
@rollback:
    sudo nixos-rebuild switch --rollback

# Useful for "deploy what's on github" without touching the local tree.
@deploy:
    nh os switch github:phibkro/homelab -H $(hostname)


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


# Run non-VM Nix checks; no host activation.
@check:
    bash scripts/check-nix.sh fast

# Run every metadata-selected Nix check, including disposable VMs.
@check-all:
    bash scripts/check-nix.sh all

# Run all disposable NixOS VMs, or one exact check name.
@check-vm name="":
    bash scripts/check-nix.sh vm {{quote(name)}}

# during restructures or when a long-running drift is suspected.
@check-migration:
    bash lint/checks/path-coherence.sh .
    bash tests/path-coherence_test.sh lint/checks/path-coherence.sh

# Run the music-ingest real-filesystem acceptance journey in its pinned shell.
@test-music-ingest:
    devenv test

# Run the disposable transient Firecracker Environment journey. It requires KVM and never activates or deploys a host configuration.
@test-self-hosted-firecracker:
    #!/usr/bin/env bash
    set -euo pipefail
    repository_root="${ADLC_REPOSITORY_ROOT:-{{justfile_directory()}}/../adlc-os}"
    repository_root="$(realpath "$repository_root")"
    if [ ! -f "$repository_root/apps/local-environment-controller/src/main.ts" ]; then
      echo "ADLC_REPOSITORY_ROOT must name an adlc-os checkout" >&2
      exit 2
    fi
    ADLC_REPOSITORY_ROOT="$repository_root" ADLC_REAL_HOST_MODE=transient exec bun tests/real-host-self-hosted-firecracker.ts

# Format all .nix files via the project formatter (nixfmt via nixfmt-tree).
@fmt:
    nix fmt

# Update flake.lock (re-pin inputs). Re-pinning unstable should be deliberate.
@update-flake:
    nix --extra-experimental-features "nix-command flakes" flake update


# AST-splice a scalar into a `.nix` file, then run the project formatter. Complex exprs: edit by hand.
@set file attr value:
    # nix-editor's -f flag uses nixpkgs-fmt; project uses nixfmt via
    # nixfmt-tree (see flake.nix `formatter.${system} = pkgs.nixfmt-tree;`).
    # Skip -f and run `nix fmt` after to keep style consistent.
    nix run github:snowfallorg/nix-editor -- -i -v '{{value}}' '{{file}}' '{{attr}}'
    nix fmt -- '{{file}}'
    @echo "--- diff ---"
    @git --no-pager diff -- '{{file}}' | head -30
    @echo "--- review the diff, then explicitly activate with just activate-test or just rebuild ---"

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


# Drop into another host's shell.
@ssh host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}}


# Generate a table-of-contents from a doc's `## ` section headings — entry-point into long docs.
@generate-toc doc:
    grep '^## ' docs/{{doc}}.md | sed 's/^## /  /'
