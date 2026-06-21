#!/usr/bin/env just --justfile
# Operator-facing recipes for the `nori.backups` concern. Imported via
# the root Justfile; recipes appear at top level (no namespace prefix).
#
# Restic concepts:
#   * repo    — one per logical dataset (user-data, media-irreplaceable, …)
#   * target  — physical destination (onetouch, mp510)
#   * snapshot — restic's content-addressed point-in-time view
#
# Health checks live in `tests/tests.just § test-backups`. These
# recipes are the manual-trigger surface: kick a job out-of-cycle,
# verify a check ran, list snapshots, dry-run a restore.

# Repos: user-data | media-irreplaceable | open-webui | etc.
# Usage: just backup <repo>
#
# Trigger an immediate backup of a repo (out-of-cycle from the scheduled timer).
@backup repo:
    sudo systemctl start restic-backups-{{repo}}.service && journalctl -u restic-backups-{{repo}}.service -f

# Trigger restic check now (weekly cadence is automatic via systemd timer).
@check-restic:
    sudo systemctl start restic-check-weekly.service && journalctl -u restic-check-weekly.service -f

# Three tiers split by cost + cadence; `services` is cheap and fast,
# `user-data` is the heavy one, `all` includes media-irreplaceable
# (multi-hour). Usage: just restore-drill [services|user-data|all]
#
# Verify backups are *restorable* (not just *recorded*) by replaying the latest snapshot.
@restore-drill tier="services":
    sudo systemctl start restore-drill-{{tier}}.service && journalctl -u restore-drill-{{tier}}.service -f

# List restic snapshots for a repo. Usage: just list-snapshots <repo>
@list-snapshots repo:
    sudo /run/current-system/sw/bin/restic -r /mnt/backup/{{repo}} --password-file /run/secrets/restic-password snapshots
