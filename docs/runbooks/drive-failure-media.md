# Media drive failure

**Recovery target**: depends on surviving copies. No current media backup
coverage has been verified.

## Symptom

The IronWolf Pro 4TB (`/mnt/media`) fails. Symptoms:

- `mnt-media-*.mount` units fail to start
- btrfs checksum errors flood the journal
- the configured by-id device does not enumerate

## Establish what survives

IronWolf Pro is the cold-data HDD; the two SSDs hold hot data. Inspect the
OneTouch destination selected by `src/inventory/backup.nix` and preserved MP510
archives. The [September 19 inspection](../archive/reports/2026-09-19-backup-evidence.md)
established service-state restore evidence, not a media restore. The earlier
preflight found an approximately 40 KiB MP510 `media-irreplaceable` directory;
neither a repository name nor that historical size establishes usable coverage.

Inspect surviving devices, historical archives, and any independently held
copies before provisioning a replacement. Same-disk snapshots cannot recover
from loss of the disk. Application dumps retained on another surviving disk
may help restore application state, but do not reconstruct missing media.

## Procedure

### 1. Replace the drive

Power down. Swap in a new ≥4 TB drive. Boot.

### 2. Identify the new drive's by-id

```bash
ls /dev/disk/by-id/
```

Find the new drive (by model + serial). Update `src/infra/workstation/disko-media.nix` if the by-id changed.

### 3. Provision only the verified replacement drive

This step is destructive and requires explicit operator approval. Confirm the
selected module evaluates to the replacement disk alone; never include MP510
or the workstation root disk in its scope.

```bash
cd /tmp/nix-migration   # or wherever the flake is
sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest -- \
  --mode disko src/infra/workstation/disko-media.nix
```

Wipes + creates the btrfs filesystem with the subvolumes declared in the reviewed disk configuration.

### 4. Inspect archives before restoring

Use a protected recovery credential obtained through its authorized provider;
do not assume `/run/secrets/restic-password` is available on a recovery system.
These commands are templates for an existing verified repository:

```text
sudo restic -r <existing-repository> --password-file <protected-credential-file> snapshots
sudo restic -r <existing-repository> --password-file <protected-credential-file> ls <snapshot-id>
sudo restic -r <existing-repository> --password-file <protected-credential-file> restore <snapshot-id> --target <disposable-directory>
```

Validate restored files and paths before copying them to the replacement disk.
If no usable snapshot or other copy exists, record that data as unrecovered;
do not create a new repository and mistake it for the lost backup.

### 5. Re-derive streaming media

For media that can be acquired again, recovery options include:

- **Stremio + cloud sources** (if you stream rather than download)
- **Re-rip / re-download** the things you actually watch (most homelab streaming libraries have a long tail of "watched once, never again" — don't re-acquire it all)
- **Sonarr / Radarr** (when the arr stack is set up) automate this — they re-grab from indexers based on the library state

If content is irreplaceable, record its protection requirement explicitly.
Changing its directory or value tier does not establish a usable backup;
verify inclusion in the selected destination and a fresh restore.

### 6. Verify

Inspect recovered file contents and application behavior. Record the actual
archive, snapshot ID, recovered paths, and remaining loss. Use the
[OneTouch cutover runbook](onetouch-backup-cutover.md) to re-establish backups
after recovery; a configured destination is not recovery evidence.

## Failure-mode notes

- **Partial drive failure** (some sectors readable, some not): `btrfs scrub` may recover what's recoverable before you reach for restic. Run on the still-mounted drive: `sudo btrfs scrub start /mnt/media`. Uncorrectable errors mean scrub could not repair those blocks; preserve the failing device and assess backup or specialist recovery options before destructive changes.
- **Transport/controller failure** vs **drive failure**: test the configured connection and the drive independently before assuming the drive is dead.
- **Don't run `disko` on a drive whose data hasn't been confirmed lost.** disko's `--mode disko` is destructive. Confirm via `smartctl -a` and a btrfs scrub before reformatting.
