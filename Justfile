#!/usr/bin/env just --justfile
# Common workflows for the nori homelab flake.
#
# Install: `brew install just` on macOS; `pkgs.just` (already in
# common/base.nix systemPackages) on NixOS hosts.
#
# Run `just` to see all recipes; run `just <name>` to invoke one.
# `just rebuild` is the default (running `just` with no args = rebuild).
#
# Most recipes take an optional `host` arg — defaults to nori-station.
# Pass a different name to deploy/inspect elsewhere when nori-laptop /
# nori-macbook land:
#   just rebuild nori-laptop
#   just status nori-laptop
#   just logs nori-laptop sshd
#
# The host value must match `hosts/<name>/` AND
# `nixosConfigurations.<name>` in flake.nix. Tailnet MagicDNS resolves
# `<name>.saola-matrix.ts.net` to the right machine.

default_host := "nori-station"
user         := "nori"
remote       := "/tmp/nix-migration"
tailnet      := "saola-matrix.ts.net"

# rsync flags — BSD openrsync compatible (Mac default rsync is openrsync; some
# GNU flags like --info=stats2 fail silently on it). See docs/gotchas.md.
rsync_args := "-aH --no-owner --no-group --partial --delete --exclude='.git' --exclude='result' --exclude='inventory-*'"

# Default recipe — sync working tree + rebuild + activate on the default host.
default: rebuild

# Show all recipes with their docs.
@list:
    just --list --justfile {{justfile()}}

# === build / deploy ===

# Sync working tree to <host> and run nh os switch.
@rebuild host=default_host:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote}}/
    ssh {{user}}@{{host}}.{{tailnet}} 'cd {{remote}} && nh os switch . -H {{host}}'

# Build but don't activate (handy to confirm the closure builds before applying).
@build host=default_host:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote}}/
    ssh {{user}}@{{host}}.{{tailnet}} 'cd {{remote}} && nh os build . -H {{host}}'

# Activate at next boot only (useful for kernel/initrd changes).
@boot host=default_host:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote}}/
    ssh {{user}}@{{host}}.{{tailnet}} 'cd {{remote}} && nh os boot . -H {{host}}'

# Git-based deploy — commit-push then rebuild from the public flake on GitHub.
# No rsync; takes the latest pushed commit instead of the local working tree.
@deploy host=default_host:
    git push origin main
    ssh {{user}}@{{host}}.{{tailnet}} 'nh os switch github:phibkro/homelab -H {{host}}'

# Roll back to the previous generation.
@rollback host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'sudo nixos-rebuild switch --rollback'

# === validate ===

# Run nix flake check (statix + deadnix + nixfmt + eval) on <host>.
@check host=default_host:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote}}/
    ssh {{user}}@{{host}}.{{tailnet}} 'cd {{remote}} && nix --extra-experimental-features "nix-command flakes" flake check'

# Format all .nix files via nixfmt-rfc-style on <host>; pull formatted files back.
@fmt host=default_host:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote}}/
    ssh {{user}}@{{host}}.{{tailnet}} 'cd {{remote}} && nix-shell -p nixfmt-rfc-style --command "find . -name \"*.nix\" -not -path \"./result*\" -exec nixfmt {} +"'
    rsync {{rsync_args}} {{user}}@{{host}}.{{tailnet}}:{{remote}}/ ./

# Update flake.lock on <host> and pull it back. Re-pinning unstable should be deliberate.
@update host=default_host:
    rsync {{rsync_args}} ./ {{user}}@{{host}}.{{tailnet}}:{{remote}}/
    ssh {{user}}@{{host}}.{{tailnet}} 'cd {{remote}} && nix --extra-experimental-features "nix-command flakes" flake update'
    rsync {{rsync_args}} {{user}}@{{host}}.{{tailnet}}:{{remote}}/flake.lock ./flake.lock

# === observe ===

# Drop into <host>'s shell.
@ssh host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}}

# Quick health summary on <host>: failed units, disk usage, restic + btrbk timer state.
@status host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'echo "=== failed units ==="; systemctl --failed --no-pager; echo; echo "=== disks ==="; df -h / /mnt/media /mnt/backup 2>/dev/null; echo; echo "=== timers (restic + btrbk) ==="; systemctl list-timers "restic-*" "btrbk-*" --no-pager 2>/dev/null'

# Tail a systemd unit's journal on <host>. Usage: just logs <host> <unit>
@logs unit host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'sudo journalctl -u {{unit}} -n 50 --no-pager'

# Live-tail a unit on <host>. Usage: just follow <host> <unit>
@follow unit host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'sudo journalctl -u {{unit}} -f'

# === backup ===

# Trigger an immediate backup on <host>. Usage: just backup <repo> [<host>]
# Repos: user-data | media-irreplaceable | open-webui
@backup repo host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'sudo systemctl start restic-backups-{{repo}}.service && journalctl -u restic-backups-{{repo}}.service -f'

# Trigger restic check now on <host> (weekly cadence is automatic via systemd timer).
@restic-check host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'sudo systemctl start restic-check-weekly.service && journalctl -u restic-check-weekly.service -f'

# List restic snapshots for a repo on <host>. Usage: just snapshots <repo> [<host>]
@snapshots repo host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'sudo /run/current-system/sw/bin/restic -r /mnt/backup/{{repo}} --password-file /run/secrets/restic-password snapshots'

# === auth ===

# Generate raw + PBKDF2 hash for a new lan-route OIDC client and
# print two paste-ready YAML lines for sops. Output is sensitive;
# runs on the host (openssl + authelia via nix shell) and the
# values land in your terminal — copy both lines, paste into
# `sops secrets/secrets.yaml`, then `just rebuild`.
# Usage: just oidc-key <name> [<host>]
@oidc-key name host=default_host:
    ssh {{user}}@{{host}}.{{tailnet}} 'nix shell nixpkgs#openssl nixpkgs#authelia --command bash -s -- {{name}}' < scripts/oidc-key.sh
