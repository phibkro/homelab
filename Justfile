#!/usr/bin/env just --justfile
# Common workflows for the nori homelab flake.
#
# Install: `brew install just` on macOS; `pkgs.just` (already in
# common/base.nix systemPackages) on NixOS hosts.
#
# Run `just` to see all recipes; run `just <name>` to invoke one.
# `just rebuild` is the default (running `just` with no args = rebuild).

host       := "nori@192.168.1.181"
remote     := "/tmp/nix-migration"
hostname   := "nori-station"

# rsync flags — BSD openrsync compatible (Mac default rsync is openrsync; some
# GNU flags like --info=stats2 fail silently on it). See docs/gotchas.md.
rsync_args := "-aH --no-owner --no-group --partial --delete --exclude='.git' --exclude='result' --exclude='inventory-*'"

# Default recipe — sync working tree + rebuild + activate.
default: rebuild

# Show all recipes with their docs.
@list:
    just --list --justfile {{justfile()}}

# === build / deploy ===

# Sync working tree to the host and run nh os switch (the default flow).
@rebuild:
    rsync {{rsync_args}} ./ {{host}}:{{remote}}/
    ssh {{host}} 'cd {{remote}} && nh os switch . -H {{hostname}}'

# Build but don't activate (handy to confirm the closure builds before applying).
@build:
    rsync {{rsync_args}} ./ {{host}}:{{remote}}/
    ssh {{host}} 'cd {{remote}} && nh os build . -H {{hostname}}'

# Activate at next boot only (useful for kernel/initrd changes).
@boot:
    rsync {{rsync_args}} ./ {{host}}:{{remote}}/
    ssh {{host}} 'cd {{remote}} && nh os boot . -H {{hostname}}'

# Git-based deploy — commit-push-pull-rebuild via the public flake on GitHub.
# No rsync; takes the latest pushed commit instead of the local working tree.
@deploy:
    git push origin main
    ssh {{host}} 'nh os switch github:phibkro/homelab -H {{hostname}}'

# Roll back to the previous generation.
@rollback:
    ssh {{host}} 'sudo nixos-rebuild switch --rollback'

# === validate ===

# Run nix flake check (statix + deadnix + nixfmt + eval) on the host.
@check:
    rsync {{rsync_args}} ./ {{host}}:{{remote}}/
    ssh {{host}} 'cd {{remote}} && nix --extra-experimental-features "nix-command flakes" flake check'

# Format all .nix files via nixfmt-rfc-style; pull formatted files back to Mac.
@fmt:
    rsync {{rsync_args}} ./ {{host}}:{{remote}}/
    ssh {{host}} 'cd {{remote}} && nix-shell -p nixfmt-rfc-style --command "find . -name \"*.nix\" -not -path \"./result*\" -exec nixfmt {} +"'
    rsync {{rsync_args}} {{host}}:{{remote}}/ ./

# Update flake.lock and pull it back. Re-pinning unstable should be deliberate.
@update:
    rsync {{rsync_args}} ./ {{host}}:{{remote}}/
    ssh {{host}} 'cd {{remote}} && nix --extra-experimental-features "nix-command flakes" flake update'
    rsync {{rsync_args}} {{host}}:{{remote}}/flake.lock ./flake.lock

# === observe ===

# SSH into the host (interactive shell).
@ssh:
    ssh {{host}}

# Quick health summary: failed units, disk usage, restic + btrbk timer state.
@status:
    ssh {{host}} 'echo "=== failed units ==="; systemctl --failed --no-pager; echo; echo "=== disks ==="; df -h / /mnt/media /mnt/backup; echo; echo "=== timers (restic + btrbk) ==="; systemctl list-timers "restic-*" "btrbk-*" --no-pager'

# Tail a specific systemd unit's journal. Usage: just logs <unit>
@logs unit:
    ssh {{host}} 'sudo journalctl -u {{unit}} -n 50 --no-pager'

# Follow logs live for a unit. Usage: just follow <unit>
@follow unit:
    ssh {{host}} 'sudo journalctl -u {{unit}} -f'

# === backup ===

# Trigger an immediate backup of one repo. Usage: just backup user-data | media-irreplaceable | open-webui
@backup repo:
    ssh {{host}} 'sudo systemctl start restic-backups-{{repo}}.service && journalctl -u restic-backups-{{repo}}.service -f'

# Trigger restic check now (weekly cadence is automatic via systemd timer).
@restic-check:
    ssh {{host}} 'sudo systemctl start restic-check-weekly.service && journalctl -u restic-check-weekly.service -f'

# List restic snapshots for a repo. Usage: just snapshots user-data
@snapshots repo:
    ssh {{host}} 'sudo /run/current-system/sw/bin/restic -r /mnt/backup/{{repo}} --password-file /run/secrets/restic-password snapshots'
