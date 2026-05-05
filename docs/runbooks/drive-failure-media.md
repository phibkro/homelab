# Media drive failure

**RTO**: <1 day for service config; **days** for media data — bandwidth-bound.

## Symptom

The IronWolf Pro 4TB (`/mnt/media`) fails. Symptoms:

- `mnt-media-*.mount` units fail to start
- btrfs checksum errors flood the journal
- `/dev/sda` doesn't enumerate

## What survives

- Photos, home-videos, projects, archive subvolumes — backed up by restic to OneTouch (and Pi/Hetzner when those land). Recoverable.
- Streaming media (movies, shows, music in `@streaming`) — **not backed up** per DESIGN tier policy. Re-derivable from sources.

The split is intentional: irreplaceable data has redundant copies; re-derivable data has a single copy because re-deriving is cheaper than off-site storage.

## Procedure

### 1. Replace the drive

Power down. Swap in a new ≥4 TB drive (or stop being USB-attached and migrate to internal SATA — see DESIGN open items). Boot.

### 2. Identify the new drive's by-id

```bash
ls /dev/disk/by-id/
```

Find the new drive (by model + serial). Update `hosts/workstation/disko-media.nix` if the by-id changed.

### 3. Run disko on the new drive

```bash
cd /tmp/nix-migration   # or wherever the flake is
sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest -- \
  --mode disko hosts/workstation/disko-media.nix
```

Wipes + creates the btrfs filesystem with all six subvolumes (@streaming, @photos, @home-videos, @projects, @archive, @snapshots).

### 4. Restore irreplaceable data from restic

```bash
sudo restic -r /mnt/backup/media-irreplaceable \
  --password-file /run/secrets/restic-password \
  restore latest --target /
```

The restic snapshots store the full `/mnt/media/{photos,home-videos,projects,archive}` paths; restoring with `--target /` lands them at the same paths.

This will take hours over USB depending on dataset size. Track progress:

```bash
# In another shell
sudo du -sh /mnt/media/{photos,home-videos,projects,archive}
```

### 5. Re-derive streaming media

Streaming wasn't backed up. Recovery options in priority order:

- **Stremio + cloud sources** (if you stream rather than download)
- **Re-rip / re-download** the things you actually watch (most homelab streaming libraries have a long tail of "watched once, never again" — don't re-acquire it all)
- **Sonarr / Radarr** (when the arr stack is set up) automate this — they re-grab from indexers based on the library state

If you decide a particular subset of streaming is actually irreplaceable (a specific home-recorded format, etc.), reclassify it: move from `@streaming` to `@projects` so the next backup sweep covers it.

### 6. Verify

```bash
ls /mnt/media/{photos,home-videos,projects,archive}
sudo restic -r /mnt/backup/media-irreplaceable \
  --password-file /run/secrets/restic-password \
  check
```

## Failure-mode notes

- **Partial drive failure** (some sectors readable, some not): `btrfs scrub` may recover what's recoverable before you reach for restic. Run on the still-mounted drive: `sudo btrfs scrub start /mnt/media`. If scrub reports uncorrectable errors, the data on those blocks is gone — restic restore is the only path.
- **USB enclosure failure** vs **drive failure**: same drive in a different enclosure may work fine. Test before assuming the drive is dead.
- **Don't run `disko` on a drive whose data hasn't been confirmed lost.** disko's `--mode disko` is destructive. Confirm via `smartctl -a` and a btrfs scrub before reformatting.
