# Storage pressure prevention

## Goal

Prevent filesystem allocation pressure from disabling application saves, backups, and the workstation desktop.

The operator approved implementation after the 7 October storage incident. This change targets the workstation only.

## Constraints

- Preserve current files, credentials, application profiles, and uncommitted operator work.
- Do not delete additional snapshots or reduce the declared backup retention.
- Keep one pressure measurement and classification construct for alarms, maintenance, and snapshot guards.
- Extend the existing disk alarm and alert delivery path. Do not add a competing monitor.
- Identify physical filesystems independently of subvolume mountpoints. Serialize allocation maintenance with snapshot operations on each filesystem.
- Never run an unrestricted balance, metadata-profile conversion, or automatic data deletion.
- Separate only explicit disposable cache directories. Do not classify the whole cache tree as disposable.
- Preserve cache contents during migration. Refuse migration while a cache writer owns the affected paths.
- Build and exercise the changed behavior before workstation activation. Do not publish or deploy other hosts.

## Behavior

### Pressure alarm

Retain the ordinary filesystem usage alarm. Add Btrfs metadata usage and unallocated device space.

The classifier distinguishes high metadata utilization with room to expand from high utilization without expansion workspace.

A failed measurement is an error, not a healthy filesystem. Alerts name the affected filesystem and actionable allocation measurements.

### Allocation maintenance

A scheduled worker checks allocation headroom before it moves data. It first reclaims empty data block groups.

Any further compaction uses explicit utilization and block-group limits. Each run has a finite work limit.

The worker preserves metadata redundancy and file contents. It defers when another exclusive filesystem operation owns the filesystem.

An exhausted workspace produces an actionable error. The worker does not retry indefinitely or delete data.

### Snapshot policy

Keep the existing retention and off-disk send policy. Under critical pressure, run only cleanup permitted by that policy.

Check pressure again before a new snapshot. If pressure remains critical, refuse the snapshot and report failure through the existing alert path.

Do not report a skipped snapshot as a successful backup.

### Disposable caches

Use the filesystem value-tier registry as the cache classification source. Derive snapshot and recursive-backup exclusions from that registry.

Use subvolume boundaries for selected caches. Preserve source files, personal documents, browser state, and credentials outside the selected paths.

The migration checks writer ownership and preserves contents. A busy cache remains unchanged and produces an explicit blocker.

## Acceptance gates

1. A filesystem with plentiful free data, near-full metadata, and no expansion workspace produces an allocation-pressure alert.
2. High metadata utilization with adequate expansion workspace does not produce the same critical classification.
3. Non-Btrfs filesystems retain the existing ordinary-space alarm behavior.
4. Invalid or unavailable allocation measurements cannot produce a healthy result.
5. Maintenance performs only bounded data-block compaction and does not overlap a snapshot operation on the same filesystem.
6. A pressure-blocked snapshot leaves retention unchanged and reports a failure rather than a new backup.
7. A selected cache is absent from a parent subvolume snapshot and a recursive backup. Protected neighboring files remain included.
8. Cache migration preserves contents and refuses an active writer.
9. The installed workstation units use the verified packages and policies. Real filesystem probing and alert delivery are exercised.

## Existing components

Reuse the filesystem registry, btrbk, the disk alarm, the shared alert command, NixOS module composition, and the existing integration-test registration.

The implementation must update the existing storage reference and recovery runbook after runtime verification.
