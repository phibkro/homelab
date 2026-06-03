---
name: gotcha-pre-phase5-backups
description: USE WHEN touching `scripts/backup.sh` or any pre-Phase-5 rsync-to-exfat backup snapshot — there's no integrity verification, no post-write check, no comparison across runs. Files can disappear and the manifest still claims success. Treat any pre-Phase-5 backup as snapshot-of-intent, not source-of-truth. Phase 5+ uses restic with `restic check` + content-addressed integrity.
---

# Pre-Phase-5 backups (`scripts/backup.sh`) have no integrity verification

`scripts/backup.sh` writes a manifest from in-the-moment `du` of the destination directory. There's no post-write verification, no comparison on subsequent runs. Files can disappear between backup and restore (manual deletion, exfat corruption) and the manifest still claims success. Treat any pre-Phase-5 rsync-to-exfat backup as a snapshot of intent, not a guaranteed source of truth.

For Phase 5+, restic (`backup/restic.nix`) provides `restic check` + content-addressed integrity by design.
