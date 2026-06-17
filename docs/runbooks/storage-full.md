# Storage full / media services down

**RTO**: 30–60 min once you find the wedge. The first 5 minutes recover the SSD; the rest is media-drive cull.

## Symptom

Jellyseerr / Jellyfin / *arr stack misbehaving, downloads not completing, syncthing failed. Almost always means a btrfs filesystem hit 100%.

## The wedge pattern (most likely cause)

`/mnt/media` (IronWolf, @downloads subvol) fills up with completed media → qBittorrent can't finalize-move new downloads off the NVMe → partials pile up in `/var/lib/qBittorrent/qBittorrent/incomplete/` on the SN750 → root NVMe also fills → everything that needs to write breaks at once.

btrbk retention (`7d 4w 6m` on root, `14d 8w 12m` on media) works in the steady state, but **at 100% full btrbk can't even prune** — subvolume delete needs metadata reserve. So snapshot backlog accumulates as a secondary symptom; it's not the root cause.

Pre-2026-05-14 prevention gaps that let this happen:

- No free-space alerts (added 2026-05-14 — `modules/services/disk-alert.nix`).
- No Sonarr/Radarr/Lidarr `MinimumFreeSpaceWhenImporting` setting. Set per-instance via UI on first-run — see the *arr modules' setup comments.

## Diagnose

```bash
df -h                                            # which drives are full
sudo btrfs filesystem usage /                    # root reality
sudo btrfs filesystem usage /mnt/media/library   # media reality (any subvol works)
sudo du -sh /var/lib/* 2>/dev/null | sort -h | tail -15
du -sh /mnt/media/downloads/* 2>/dev/null | sort -h
ls /.snapshots/ | wc -l
ls /mnt/media/.snapshots/ | wc -l
systemctl list-units --type=service --state=failed
```

Box-specific names worth remembering:

- jellyseerr unit is `seerr.service` (not `jellyseerr`).
- *arr stack: `sonarr radarr lidarr bazarr`.
- qBittorrent state dir: `/var/lib/qBittorrent/qBittorrent/` (config, data, incomplete, downloads, cache). The 100s-of-GB consumer when wedged is `incomplete/`.
- Root snapshots: `/.snapshots/{home,lib,share}.<YYYYMMDD>T<HHMM>`.
- Media snapshots: `/mnt/media/.snapshots/{archive,home-videos,library,photos,projects}.<...>`. `@downloads` is **not** snapshotted (re-derivable tier per `modules/infra/storage/default.nix`) — deleting from `/mnt/media/downloads/` frees space immediately.

## Stage 1 — stop the writers

```bash
sudo systemctl stop qbittorrent seerr sonarr radarr lidarr
```

## Stage 2a — free the root NVMe

The qBittorrent partials are the dominant consumer:

```bash
sudo rm -rf /var/lib/qBittorrent/qBittorrent/incomplete/*
df -h /
```

If the snapshot backlog also needs trimming, btrbk's next daily run will catch up automatically once the FS has metadata headroom. If you want to force it sooner:

```bash
sudo systemctl start btrbk-root.service
```

Or manually keep last N per prefix:

```bash
ls -1 /.snapshots/ | awk -F. '{print $1}' | sort -u | while read prefix; do
  ls -1 /.snapshots/ | grep "^${prefix}\." | sort | head -n -3 \
    | while read s; do sudo btrfs subvolume delete "/.snapshots/$s"; done
done
```

## Stage 2b — trim media snapshots

Same pattern, same `btrbk-media.service` shortcut if you want to force it. Manual:

```bash
ls -1 /mnt/media/.snapshots/ | awk -F. '{print $1}' | sort -u | while read prefix; do
  ls -1 /mnt/media/.snapshots/ | grep "^${prefix}\." | sort | head -n -3 \
    | while read s; do sudo btrfs subvolume delete "/mnt/media/.snapshots/$s"; done
done
```

## Stage 3 — cull actual media

Prefer the Sonarr/Radarr UIs so their DBs stay consistent. If yolo:

```bash
du -sh /mnt/media/downloads/movies/* | sort -h | tail -20
du -sh /mnt/media/downloads/shows/*  | sort -h | tail -20
rm -rf "/mnt/media/downloads/movies/<thing>"
```

## Bring it back

Order matters — start qBittorrent **alone** first and remove the orphaned torrents (files we deleted) via the webui, *then* start the *arr stack and seerr. Otherwise the *arr stack immediately re-queues them.

```bash
sudo systemctl start qbittorrent
# webui at https://downloads.home.phibkro.org — remove orphaned torrents
sudo systemctl start sonarr radarr lidarr
sudo systemctl start seerr
df -h
```

## Gotchas

- `btrfs subvolume delete` returns immediately; the cleaner reclaims space async. `df` lags for minutes. Force with `sudo btrfs subvolume sync <path>` or just wait.
- Don't `rm -rf` a btrfs subvolume — works but leaves the subvolume entry behind for the cleaner to chase.
- At 100% full even deletes can fail (need metadata reserve). If stuck: `sudo btrfs balance start -dusage=10 /<mountpoint>` to reclaim mostly-empty data chunks first.
- Stop writers *before* deleting their files; otherwise space stays marked-used until the process exits.
- Today's daily snapshot will pin anything you delete today until the next btrbk run promotes/prunes. To free same-day, delete today's snapshot after the cull.
