---
summary: btrfs layout, subvolumes per value tier, the `nori.fs` abstraction,
  database-on-btrfs CoW interactions, snapshot policy, backup repos + retention.
  The "where data lives and how it survives" reference.
---

# Storage

Btrfs everywhere on Linux. Mount options: `compress=zstd:3,noatime`. Subvolumes are split by value tier (snapshot/backup policy), not directory hierarchy.

## Value tiers (the protection decision tree)

| Tier | Examples | Snapshot | Local backup (Pi) | Off-site (Hetzner) |
|---|---|---|---|---|
| **re-derivable** | Streaming media, Ollama models, Nix store, package caches | Weekly or none | No | No |
| **service / user** | Jellyfin DB, Immich uploads, Open WebUI, Vaultwarden vaults | Daily | Yes | Selected (Immich uploads, Open WebUI, Vaultwarden) |
| **irreplaceable** | Personal photos, home videos, finished projects, work in progress, flake repo | Hourly to daily | Yes | Yes |

System config is covered by the Git mirror to GitHub, not a backup target. See `docs/CONCEPTS.md` § value-tier protection tree.

## Workstation root (SN750, btrfs)

Subvolume layout, applied by disko during install:

| Subvolume | Mount | Snapshot | Purpose |
|---|---|---|---|
| `@` | `/` | Before each rebuild (btrbk) | System root |
| `@home` | `/home` | Hourly + daily | User data |
| `@nix` | `/nix` | Never | Re-derivable from flake |
| `@var-lib` | `/var/lib` | Daily | Service state |
| `@srv-share` | `/srv/share` | Daily | Family-shared docs, Samba-accessible |
| `@snapshots` | `/.snapshots` | N/A | Snapshot target |

`@var-lib` separation lets service-state churn snapshot on its own cadence without polluting `@` snapshots. `@srv-share` is the explicit shared path referenced in the access matrix.

## Workstation media (IronWolf Pro, btrfs)

Disko-managed. Reformatted from exfat in Phase 2 (executed during Phase 5).

| Subvolume | Mount | Snapshot | Local backup | Off-site |
|---|---|---|---|---|
| `@streaming` | `/mnt/media/streaming` | Weekly · keep 2 | No | No |
| `@photos` | `/mnt/media/photos` | Daily · keep 14 + monthly · keep 12 | Yes | Yes |
| `@home-videos` | `/mnt/media/home-videos` | Weekly · keep 4 | Yes | Yes |
| `@projects` | `/mnt/media/projects` | Weekly · keep 4 | Yes | Yes |
| `@library` | `/mnt/media/library` | Daily · keep 14 | Yes | Yes |
| `@archive` | `/mnt/media/archive` | Weekly · keep 4 | Yes | No (legacy machine backups; not off-site-worthy) |
| `@snapshots` | `/mnt/media/.snapshots` | N/A | N/A | N/A |

`@streaming` holds re-derivable content (auto-grabbed by *arr + qBittorrent staging). `@library` holds curated content the operator assembled by hand (books, comics) — distinct content type from `@projects` (work products), same backup tier.

## Pi storage

`@` on USB SSD (root). USB HDD mounted at `/mnt/backup` holds the restic repository for workstation's irreplaceable data and service state. Restic encrypts client-side, so the HDD's filesystem doesn't matter for security; ext4 is the boring default.

## Database-on-btrfs CoW interaction

Two interactions to handle separately:

### Write-performance (`chattr +C` / `nodatacow`)

Database directories should have CoW disabled to avoid write amplification. For Immich's Postgres in `/var/lib/immich/database`, set the directory `+C` before initialization, or place service state on a subvolume mounted with `nodatacow`. This is a **performance fix, not backup-consistency**.

### Backup-consistency (logical dumps before backup)

Filesystem snapshot of a running database produces inconsistent state. Backup correctness requires a logical dump (`pg_dump` / SQLite `.backup` API) before restic touches the data. See SERVICES.md § Backup patterns.

## Filesystem context (`nori.fs`)

`nori.fs.<n>` is Reader-shaped — declared alongside the host's disko config; each entry pairs a path with a value tier (`re-derivable` | `user` | `service` | `irreplaceable`). Service modules read `config.nori.fs.<n>.path`; backup repo paths + btrbk subvolume lists derive from the tier filter.

Schema in `modules/effects/fs.nix`; declarations in `machines/workstation/disko*.nix`. Adding a media subvolume = one declaration; backup + snapshot wiring follows.

## Snapshot policy (btrbk)

`modules/server/backup/btrbk.nix` declares two btrfs subvolume snapshot instances (root + media). Daily by default; retention follows the value-tier table above.

Both `restic-backups-*` and `btrbk-*` units get `OnFailure = [ "notify@%n.service" ]` so silent failures fire an ntfy alert.

## Backup destinations + retention

Two restic repositories per service, three retention policies.

| Path / service | Pi (local fast restore) | Hetzner (off-site disaster) |
|---|---|---|
| `/home` | Daily · keep 14d + 4w | Weekly · keep 4w + 12m |
| `/srv/share` | Daily · keep 14d + 4w | Weekly · keep 4w + 12m |
| Immich (dumps + uploads) | Daily · keep 7d + 4w | Daily · keep 7d + 4w + 12m |
| Open WebUI dump | Daily · keep 7d + 4w | Weekly · keep 4w + 12m |
| Other service state | Daily · keep 7d | Not backed up (re-derivable) |
| `@streaming` | Not backed up | Not backed up |
| `@photos`, `@home-videos`, `@projects` | Daily · keep 14d + 4w | Daily · keep 4w + 12m + yearly indefinite |

## Hetzner Storage Box sizing

Pricing (April 2026): BX11 (1TB) ~3.20 EUR/mo, BX21 (5TB) ~10.80 EUR/mo, BX31 (10TB) ~20.80 EUR/mo. Plans scale up/down without data migration; cancellation any time.

Initial sizing: start at BX11 (1TB) if irreplaceable data is <500GB. Re-evaluate when home-videos archive grows past 700GB. Tracked in `docs/capacity-baseline.md`, reviewed quarterly.

## Backup verification

| Cadence | Action |
|---|---|
| Weekly | `restic check` (metadata only) |
| Monthly | `restic check --read-data-subset=10%` (rolling sample; full repo covered every ~10 months) |
| Quarterly | **Restore drill** — restore one subvolume's recent snapshot to `/var/restore-test/`, diff against live, document time |

Failure of any of these alerts via ntfy. Quarterly drill is the **real RTO measurement**, not the unit-test green light.

## Backup intent abstraction (`nori.backups`)

`nori.backups.<n>` (paths or skip + optional `tier`) drives every restic job. `tier` (`service` | `user` | `irreplaceable`) drives the default `pruneOpts` retention curve. The `every-service-has-backup-intent` flake check ensures no service module ships without declaring intent — either real paths or an explicit `.skip = "<reason>"`.

The DynamicUser `StateDirectory` symlink-trap assertion derives from `config.systemd.services` introspection — self-maintaining. See `.claude/skills/gotcha-dynamicuser-statedirectory-symlink/`.

Schema in `modules/effects/backup.nix`. Cross-cutting infra (sops password, check timers) is in `modules/server/backup/restic.nix`. Restic repos live at `/mnt/backup/<job>` (OneTouch ext4); Hetzner Storage Box is still on the roadmap as the second per-job repo.
