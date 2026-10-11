# Storage full / media services down

**RTO**: 30–60 min once you find the wedge. The first 5 minutes recover the SSD; the rest is media-drive cull.

## Symptom

Jellyseerr / Jellyfin / *arr stack misbehaving, downloads not completing, syncthing failed. Almost always means a btrfs filesystem hit 100%.

## The wedge pattern (most likely cause)

`/mnt/media` (IronWolf, @downloads subvol) fills up with completed media → qBittorrent can't finalize-move new downloads off the NVMe → partials pile up in `/var/lib/qBittorrent/qBittorrent/incomplete/` on the SN750 → root NVMe also fills → everything that needs to write breaks at once.

btrbk retention (`7d` on root plus received copies on the IronWolf; `7d 4w 3m` on cold media) works in the steady state, but **at 100% full btrbk can't even prune** — subvolume delete needs metadata reserve. So snapshot backlog accumulates as a secondary symptom; it's not the root cause.

Pre-2026-05-14 prevention gaps that let this happen:

- No free-space alerts (added 2026-05-14 — `src/services/disk-alert/`).
- No Sonarr/Radarr/Lidarr `MinimumFreeSpaceWhenImporting` setting. Set per-instance via UI on first-run — see the *arr modules' setup comments.


## Btrfs allocation pressure with free data space

If applications report `ENOSPC` while `df` shows free space, check Btrfs allocation first.

```sh
sudo nori-storage-pressure probe /
sudo btrfs filesystem usage /
systemctl status disk-alert.service nori-storage-pressure-maintain.service
```

The shared probe reports metadata use, unallocated device bytes, and the pressure state.
For Btrfs, pass a mountpoint to the CLI. Snapshot guards resolve nested source and receive directories to their containing mounts.
Thresholds and work limits come from `nori.storagePressure`; do not maintain another threshold list here.

`nori.observability.diskAlert.mutedCriticalMountpoints` suppresses critical notifications for selected monitored mounts.
It does not change pressure classification, snapshot guards, maintenance, warning notifications, or measurement errors.
The workstation declaration is in `src/infra/workstation/default.nix`.
A targeted override under `/run/systemd/system/disk-alert.service.d/` lasts until reboot.
Rebuild the declared configuration before reboot to retain a source-only policy change.

If workspace remains, run the configured bounded worker:

```sh
sudo systemctl start nori-storage-pressure-maintain.service
journalctl -u nori-storage-pressure-maintain.service -n 40
sudo nori-storage-pressure probe /
```

The worker holds the same filesystem locks as snapshot operations. It defers when another operation owns the filesystem.
It never runs an unrestricted balance, converts metadata profiles, or deletes data.
If workspace is exhausted, it refuses further compaction, reports the blocker in the journal, and returns 75 (`EX_TEMPFAIL`).
The aggregate exit status is 1 for any real error, otherwise 75 for any workspace refusal, otherwise 0.
Real errors include measurement failures, balance failures, and missing or unreadable exclusive-operation markers.
Errors take precedence regardless of filesystem order. The maintenance unit accepts 75 without a failure notification.
Existing lock and exclusive-operation deferrals still return 0. `with-lock` independently returns 75 when its lock is busy.

Native scrub checks integrity but does not create allocation workspace. The workstation derives one monthly scrub per physical Btrfs filesystem from its storage declarations.
Before the first run, the operator must measure at least 20% CPU, memory, swap, and I/O headroom.
The scrub timers are deliberately not persistent: activation does not trigger missed runs. Missed scrubs need a reviewed reschedule.

Before any deletion, identify the exact files or snapshots and obtain operator approval.
Do not reset application profiles or delete the entire cache tree. Some cache directories contain credentials and user work.
After recovery, exercise an application save and check its result. A passing allocation probe does not establish application database integrity.

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
- Media snapshots: `/mnt/media/.snapshots/{archive,home-videos,library,photos,projects}.<...>`. `@downloads` is **not** snapshotted (re-derivable tier per `src/infra/common/nixos/storage/default.nix`) — deleting from `/mnt/media/downloads/` frees space immediately.
- Received workstation root history: `/mnt/media/.snapshots/workstation-root/{home,share,nori,lib}.<...>` (btrbk-root target; see `retention.workstationRoot` in `src/inventory/backup.nix`).

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

Received root history in `/mnt/media/.snapshots/workstation-root/` is the
next candidate. Keep at least the newest snapshot per prefix: it is the
incremental parent for the next send. Deleting it forces a full send.

```bash
d=/mnt/media/.snapshots/workstation-root
sudo ls -1 "$d" | awk -F. '{print $1}' | sort -u | while read prefix; do
  sudo ls -1 "$d" | grep "^${prefix}\." | sort | head -n -3 \
    | while read s; do sudo btrfs subvolume delete "$d/$s"; done
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
- An allocation-pressure recovery can require workspace before compaction. Use the configured bounded worker, not an unrestricted balance command.
- Stop writers *before* deleting their files; otherwise space stays marked-used until the process exits.
- A daily snapshot can retain deleted blocks. Delete additional snapshots only with approval for the exact restore points.
