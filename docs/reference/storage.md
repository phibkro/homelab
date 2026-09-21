---
summary: SSD hot storage, IronWolf Pro cold storage, local rollback snapshots, and OneTouch backup policy.
---

# Storage

The intended placement separates access needs from protection:

| Storage | Role |
|---|---|
| Workstation NVMe SSDs | Desktop, GPU, media-service, and working data |
| Adelie NVMe SSD | SSD-local application state and re-derivable Attic chunks |
| IronWolf Pro HDD | Cold media, libraries and archives |
| OneTouch HDD | Independent backup disk; destination policy in `inventory/backup.nix` |

Existing MP510 backup archives remain where they are until a reviewed move or
retention decision. This source cleanup does not relocate or delete disk data.

## Authoritative declarations

`inventory/disks.nix` owns the portable external-disk identities, filesystem
contracts, roles and declared attachment host for IronWolf Pro and OneTouch.
It intentionally excludes NVMe boot disks, whose layout belongs to each host's
own disko module. Workstation's media and backup consumers derive their device
paths from that registry. `nori.fs` entries pair paths with value tiers; the
[generated filesystem documentation](../generated/fs.md) comes from those
declarations. `inventory/datasets.nix` owns shared dataset contracts.

Hot/cold placement describes access patterns. Value tiers describe the cost of
losing data; they are separate decisions. Media already on IronWolf remains on
that HDD, while active service state and working trees remain on SSD storage.

## Backup policy and observed recovery

[`inventory/backup.nix`](../../inventory/backup.nix) owns destination selection
and its enable switch. Workstation writes directly to its attached OneTouch.
Pi and Adelie use separate restricted workstation SFTP accounts and namespaces
backed by that disk. The [generated backup reference](../generated/backups.md)
lists every evaluated job. The
[generated recovery view](../generated/recovery-evidence.md) joins declared
workload recovery models, evaluated backup mechanics, and recorded evidence
reports. [Service patterns](services.md) explain the model choices.

Configuration, mounted storage, successful backups, and usable restores are
separate evidence. The [September 19 inspection](../archive/reports/2026-09-19-backup-evidence.md)
records the enabled source, mounted drive, workstation service-state restore,
and Pi transport, freshness, metadata checks, and configuration restore. The
[Pi-hole drill](../archive/reports/2026-09-21-pihole-recovery-drill.md) proves
one consumer-visible appliance recovery. The
[Pi host reconstruction drill](../archive/reports/2026-09-21-pi-host-reconstruction-drill.md)
connects a clean, converged ARM guest and reboot to current restored Pi-hole
state and endpoints. The
[Vaultwarden drill](../archive/reports/2026-09-21-vaultwarden-sqlite-recovery-drill.md)
proves the Adelie logical SQLite path. The
[Miniflux drill](../archive/reports/2026-09-21-miniflux-postgresql-recovery-drill.md)
proves the Adelie PostgreSQL path. The
[Stremio drill](../archive/reports/2026-09-21-stremio-files-recovery-drill.md)
proves files-only service identity recovery. The
[Immich drill](../archive/reports/2026-09-21-immich-export-recovery-drill.md)
proves selective restore and import of an application-native database export.
The [user-data drill](../archive/reports/2026-09-21-user-data-recovery-drill.md)
proves bounded recovery from all three declared user-data roots. The
[Jellyfin drill](../archive/reports/2026-09-21-jellyfin-metadata-recovery-drill.md)
proves isolated application startup from restored media metadata. These
reports do not establish full user-data or media recovery, physical host
replacement, every Pi service-state restore, or full data-block integrity.
Use the [cutover runbook](../runbooks/onetouch-backup-cutover.md) when reconnecting,
changing transport, or collecting fresh recovery evidence.

## Local recovery is distinct from backup

Btrbk keeps local rollback snapshots on the same source disks. These can help
with accidental edits; they cannot recover data after that disk fails.

IronWolf's mostly-cold canonical media has separate local rollback and
independent Restic retention policies in `inventory/backup.nix` under
`retention.coldMedia`. Local retention limits how long deleted data consumes
the primary disk. Restic deduplicates unchanged chunks; retention controls
deletion history and restore choice, not a full additional copy per snapshot.
Application database dumps also remain local recovery artifacts until copied
to an independent destination.

Immich's dump location derives from `services.immich.mediaLocation`; its
`backups` directory is already beneath the photos tree. Live metadata showed
daily dumps during preflight, but their database restore validity was not
checked. For other services, use the declared logical-dump preparation rather
than assuming a copy of a running database is consistent.

Pi filesystem and service behavior belongs to Ansible under `infra/pi/`, not the
retained Nix entry-plane test adapters. Recovery procedures are indexed in the
[recovery reference](recovery.md).
