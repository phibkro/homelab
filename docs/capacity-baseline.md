# Capacity baseline

Snapshot of resource utilization, captured at quarterly cadence. Used to
inform when storage tier changes are warranted (second drive, Hetzner
upgrade, model-size reduction). The schema below is the long-term shape;
fill values at review time.

## Cadence

Quarterly. Each entry is a row keyed by date; growth trends emerge from
the row diff.

## Storage

| Subvolume | Used | Free | Δ vs prev quarter | Notes |
|---|---|---|---|---|
| `/` (`@`) | | | | system root |
| `/home` (`@home`) | | | | |
| `/var/lib` (`@var-lib`) | | | | service state |
| `/srv/share` (`@srv-share`) | | | | |
| `/mnt/media/streaming` | | | | re-derivable |
| `/mnt/media/photos` | | | | irreplaceable |
| `/mnt/media/home-videos` | | | | irreplaceable |
| `/mnt/media/projects` | | | | irreplaceable |
| `/mnt/media/library` | | | | curated |
| `/mnt/media/archive` | | | | cold |
| `/mnt/backup` | | | | restic OneTouch |

Trigger thresholds (per DESIGN.md):
- Subvolume >80% full → warn (beszel rule)
- Subvolume >90% full → urgent (beszel rule)
- IronWolf >80% → revisit second-drive-on-station decision

## Backup repositories

| Repo | Local size | Hetzner size | Snapshots | Latest check |
|---|---|---|---|---|
| `user-data` | | | | |
| `media-irreplaceable` | | | | |
| `open-webui` | | | | |

Hetzner deferred until budget allows; column kept for the day it lands.

## Compute

| Metric | Value | Notes |
|---|---|---|
| RAM idle (no Ollama loaded) | | |
| RAM with 32B-Q4 model loaded | | |
| Avg sustained CPU (evening peak) | | |
| GPU power draw idle / under inference | | from beszel agent |

## Review log

| Date | Captured by | Notes |
|---|---|---|
| _baseline pending — fill at first review_ | | |
