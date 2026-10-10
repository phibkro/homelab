---
summary: SSD hot storage, IronWolf Pro cold storage, local rollback snapshots, and OneTouch backup policy.
---

# Storage

The intended placement separates access needs from protection:

| Storage | Role |
|---|---|
| Workstation NVMe SSDs | Desktop, GPU, media-service, and working data |
| Adelie NVMe SSD | SSD-local application state |
| IronWolf Pro HDD | Cold media, libraries and archives |
| OneTouch HDD | Independent backup disk; destination policy in `src/inventory/backup.nix` |

Existing MP510 backup archives remain where they are until a reviewed move or
retention decision. This source cleanup does not relocate or delete disk data.

## Authoritative declarations

`src/inventory/disks.nix` owns the portable external-disk identities, filesystem
contracts, roles and declared attachment host for IronWolf Pro and OneTouch.
It intentionally excludes NVMe boot disks, whose layout belongs to each host's
own disko module. Workstation's media and backup consumers derive their device
paths from that registry. `nori.fs` entries pair paths with value tiers; the
[generated filesystem documentation](../generated/fs.md) comes from those
declarations. `src/inventory/datasets.nix` owns shared dataset contracts.

Hot/cold placement describes access patterns. Value tiers describe the cost of
losing data; they are separate decisions. Media already on IronWolf remains on
that HDD, while active service state and working trees remain on SSD storage.

## Backup policy and observed recovery

[`src/inventory/backup.nix`](../../src/inventory/backup.nix) owns destination selection
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
proves files-only service identity recovery on Adelie at the time of that
drill; it does not establish recovery for the current workstation placement. The
[Immich drill](../archive/reports/2026-09-21-immich-export-recovery-drill.md)
proves selective restore and import of an application-native database export.
The [user-data drill](../archive/reports/2026-09-21-user-data-recovery-drill.md)
proves bounded recovery from all three declared user-data roots. The
[Jellyfin drill](../archive/reports/2026-09-21-jellyfin-metadata-recovery-drill.md)
proves isolated application startup from restored media metadata.
The [September 21 activation](../archive/reports/2026-09-21-recovery-activation.md)
applied the cache exclusion and bounded drill configuration. It records a fresh
8.159 KiB Stremio snapshot and a successful three-file user-data restore. These
reports do not establish full user-data or media recovery, physical host
replacement, every Pi service-state restore, or full data-block integrity.
Use the [cutover runbook](../runbooks/onetouch-backup-cutover.md) when reconnecting,
changing transport, or collecting fresh recovery evidence.

## Local recovery is distinct from backup

Btrbk keeps local rollback snapshots on the same source disks. These can help
with accidental edits; they cannot recover data after that disk fails.

IronWolf's mostly-cold canonical media has separate local rollback and
independent Restic retention policies in `src/inventory/backup.nix` under
`retention.coldMedia`. Local retention limits how long deleted data consumes
the primary disk. Restic deduplicates unchanged chunks; retention controls
deletion history and restore choice, not a full additional copy per snapshot.
Application database dumps also remain local recovery artifacts until copied
to an independent destination.

Workstation root snapshots (`/home`, `/srv/share`, `/srv/nori` and `/var/lib`)
keep one week on the system NVMe, as `retention.workstationRoot` in
`src/inventory/backup.nix` declares. The same btrbk run sends them to
`/mnt/media/.snapshots/workstation-root` on the IronWolf. Phase 1 keeps only
the latest received snapshot there, so the first send does not copy the
pre-cleanup history. The planned weekly and monthly history starts in a
reviewed commit on or after the date the inventory records; the
[roadmap](../roadmap.md) lists the preconditions. The target is a root-only
directory in the IronWolf `@snapshots` subvolume, not a `nori.fs` entry:
`nori.fs` tiers select what the snapshot and Restic generators protect, and
this directory is their output. The IronWolf copy survives loss of the system
NVMe, but not loss of the workstation; Restic to the OneTouch remains the
independent backup. The [generated backup reference](../generated/backups.md)
lists each evaluated btrbk instance, its retention and its targets.

## Allocation pressure

Ordinary free data space does not establish available Btrfs metadata space.
The shared pressure construct measures metadata use and unallocated device space together.
Its policy lives in `src/infra/common/nixos/storage/pressure.nix`, under `nori.storagePressure`.

The existing disk alarm consumes that construct. It reports a warning once per warning episode, after successful delivery.
A failed measurement or critical pressure produces an urgent alert. A delivery failure fails the unit.
The bounded maintenance worker reclaims empty data block groups and compacts only the configured data-block budget.
It refuses further compaction without workspace. It never deletes files or changes metadata redundancy.

Btrbk guards use the same classification and filesystem locks.
They cover source subvolumes, snapshot directories, and off-disk receive targets.
Under critical pressure, only cleanup permitted by the existing retention runs.
The guard checks pressure again before a new snapshot. A refused snapshot fails the unit instead of reporting a successful backup.

## Re-derivable boundaries and migration

The workstation `nori.fs` registry classifies explicit package caches and
`/srv/share/projects` as `re-derivable`. Each has a nested Btrfs boundary with
`mountpoint = null`: no mount is placed over the existing path. Btrbk parent
snapshots omit nested subvolume contents; Restic still walks the live tree, so
the same registry derives exclusions for the target and migration staging /
rollback siblings.

The projects exclusion is intentional policy, not a claim that every project
is disposable. Local-only files, ignored files, and uncommitted work may have
no recoverable Git copy. Keep irreplaceable state outside this path or commit
and push it before relying on Git for recovery. Existing snapshots and Restic
history are not rewritten or deleted by this source change; retained history
continues to follow existing snapshot retention.

Home cache boundaries retain their existing guarded boot-time initialization
in `nori-subvolume-migration-home.service`, including adoption of empty
root-owned boundaries created by disko. It uses the shared per-filesystem
allocation lock. Conversion of `/srv/share/projects` is deliberately manual:
`nori-subvolume-migration-srv-share.service` has no boot target and uses the
same migration tool and lock. Before starting that unit, operators must
quiesce all project writers—including shells, editors, agents, services, and
sessions. Its `lsof` checks reduce risk but cannot prove no process can start
later. No projects migration or activation was performed as part of this
change.

The cutover reflink-copies and verifies staging, creates a read-only nested
rollback snapshot, then exchanges the verified subvolume atomically. Reflinks
share file data, but the copy still allocates new Btrfs metadata and inodes;
verify metadata headroom first. An ENOSPC during copy or rollback-snapshot
creation fails before cutover and leaves the original untouched (a failed
cleanup may leave hidden staging for review). Existing snapshots remain and
are not reclaimed by this change, so no immediate space recovery is implied.
The verified old plain-directory duplicate is removed only after comparing
the live tree and rollback snapshot against it and checking for late writers.
The retained rollback is a hidden sibling subvolume; its contents are absent
from parent snapshots and its path is included in registry-derived Restic
exclusions.

If cutover fails after exchange, the old plain directory is preserved at the
hidden staging path and Restic excludes that path. A parent Btrfs snapshot
cannot omit a plain directory: failure output explicitly warns that snapshots
still include it until the state is reviewed and resolved. Never delete the
preserved original or rollback snapshot without a separate recovery decision.

Operational checks and recovery commands are in [the storage runbook](../runbooks/storage-full.md).

The `@downloads` qgroup cap limits the IronWolf download budget.
It does not guarantee metadata headroom or account for every other writer.
The cap declaration is in `src/services/btrbk/nixos.nix`; the allocation alarm checks the remaining filesystem budget.

Immich's dump location derives from `services.immich.mediaLocation`; its
`backups` directory is already beneath the photos tree. Live metadata showed
daily dumps during preflight, but their database restore validity was not
checked. For other services, use the declared logical-dump preparation rather
than assuming a copy of a running database is consistent.

Pi filesystem and service behavior belongs to Ansible under `src/infra/pi/`, not the
retained Nix entry-plane test adapters. Recovery procedures are indexed in the
[recovery reference](recovery.md).
