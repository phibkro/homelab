---
summary: SSD hot storage, IronWolf Pro cold storage, local rollback snapshots, and deferred OneTouch backups.
---

# Storage

The intended placement separates access needs from protection:

| Storage | Role |
|---|---|
| Workstation NVMe SSDs | Hot system, application and working data; caches |
| IronWolf Pro HDD | Cold media, libraries and archives |
| OneTouch HDD | Planned backup destination after safe connection and verification |

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

## Backups are prepared, disabled

`inventory/backup.nix` is the single destination policy. Its `enabled` field is
false while OneTouch's connection is pending. The evaluated workstation has no
restic jobs, backup checks, restore schedules, receiver account, or OneTouch
mount. Pi's generated inventory disables its backup role; convergence retires
role-owned executable schedules while preserving repositories, markers,
credentials, caches and restored data.

When enabled after verification, workstation writes locally to OneTouch and Pi
uses a restricted workstation SFTP account backed by that same disk. Follow the
[OneTouch cutover runbook](../runbooks/onetouch-backup-cutover.md), including the
optional temporary Aurora route if that host becomes reachable.

Service modules retain their backup intent and consistency preparation so the
future target can be enabled without reconstructing service data manifests.
See the [generated backup reference](../generated/backups.md) and
[service patterns](services.md). Empty destination selection means no restic
jobs; declared intent is not evidence of a completed backup.

## Local recovery is distinct from backup

Btrbk keeps local rollback snapshots on the same source disks. These can help
with accidental edits; they cannot recover data after that disk fails.
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
