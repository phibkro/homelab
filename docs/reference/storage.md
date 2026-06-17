---
summary: btrfs layout, subvolumes per value tier, the `nori.fs` abstraction,
  database-on-btrfs CoW interactions, snapshot policy, backup repos + retention.
  The "where data lives and how it survives" reference.
---

# Storage

Btrfs everywhere on Linux. Mount options: `compress=zstd:3,noatime`. Subvolumes are split by value tier (snapshot/backup policy), not directory hierarchy.

## Value tiers (the protection decision tree)

| Tier | Examples | Snapshot | Restic to OneTouch + mp510 |
|---|---|---|---|
| **re-derivable** | `@downloads` (*arr + qBittorrent acquisitions), Ollama models, Nix store, package caches | None | No |
| **service / user** | Jellyfin DB, Immich uploads, Open WebUI, Vaultwarden vaults | Daily | Selected (Immich uploads, Open WebUI, Vaultwarden) |
| **irreplaceable** | Personal photos, home videos, finished projects, curated library (books/comics), flake repo | Hourly to daily | Yes |

System config is covered by the Git mirror to GitHub, not a backup target. See `docs/glossary.md` § value-tier protection tree.

## Workstation root (SN750, btrfs)

Subvolume layout, applied by disko at install. Mount options: `compress=zstd:3,noatime`.

| Subvolume | Mount | Snapshot | Purpose |
|---|---|---|---|
| `@` | `/` | Before each rebuild (btrbk) | System root + `/swapfile` (NoCoW, 8 GiB disk swap overflow tier) |
| `@home` | `/home` | Hourly + daily | User data |
| `@nix` | `/nix` | Never | Re-derivable from flake |
| `@var-lib` | `/var/lib` | Daily | Service state |
| `@srv-share` | `/srv/share` | Daily | Family-shared docs, Samba-accessible |
| `@srv-nori` | `/srv/nori` | Daily | Operator's networked working dir (Documents/Videos/Photos/Downloads/Desktop/Projects symlinked from `~`) |
| `@snapshots` | `/.snapshots` | N/A | Snapshot target |

`@var-lib` separation snapshots service-state churn on its own cadence without polluting `@`. `@srv-share` is the family-shared path; `@srv-nori` is operator-only with `home.file` out-of-store symlinks from `~/{Documents,…}`. `/swapfile` on `@` is excluded from btrbk by virtue of not being inside any tracked subvolume.

## Workstation media (IronWolf Pro, btrfs)

Disko-managed. Reformatted from exfat in Phase 2 (executed during Phase 5).

| Subvolume | Mount | Snapshot | Local backup | Off-site |
|---|---|---|---|---|
| `@downloads` | `/mnt/media/downloads` | None | No | No |
| `@photos` | `/mnt/media/photos` | Daily · keep 14 + monthly · keep 12 | Yes | Yes |
| `@home-videos` | `/mnt/media/home-videos` | Weekly · keep 4 | Yes | Yes |
| `@projects` | `/mnt/media/projects` | Weekly · keep 4 | Yes | Yes |
| `@library` | `/mnt/media/library` | Daily · keep 14 | Yes | Yes |
| `@archive` | `/mnt/media/archive` | Weekly · keep 4 | Yes | No (legacy machine backups; not off-site-worthy) |
| `@snapshots` | `/mnt/media/.snapshots` | N/A | N/A | N/A |

`@downloads` holds re-derivable acquisitions (auto-grabbed by *arr + qBittorrent staging) — explicitly NOT snapshotted, so `rm` frees space immediately when the IronWolf fills. `@library` holds curated content the operator assembled by hand (books, comics, music) — distinct content type from `@projects` (work products), same backup tier.

## Pi storage

USB-boot from Samsung FIT 128 GB. Anti-write posture (no swap, volatile journald). Pi does **not** host backup repos — those live on workstation USB drives (see Backup destinations below). Pi-as-backup-target is deferred until a real disk replaces the FIT.

## Workstation backup drives (dual-target)

Two USB-attached drives, mounted on workstation, each hosting one restic repo per service.

| Target | Mount | Drive | FS | Repo path | Trigger time |
|---|---|---|---|---|---|
| `onetouch` | `/mnt/backup` | Seagate OneTouch (physically on aurora; workstation reaches via SFTP) | ext4 | `/mnt/backup/<svc>` | per-service timer (e.g. 04:30) |
| `mp510` | `/mnt/backup-local` | Corsair Force MP510 (workstation NVMe @backup-local) | btrfs | `/mnt/backup-local/<svc>` | same timer minute |

Both restic units race on the prepareCommand `.tmp` file → wrapped in `flock` since 2026-06-07. See [[pattern-c2-sqlite-race-flock]].

Restic encrypts client-side, so the on-disk FS doesn't matter for security — ext4 (onetouch) + btrfs (mp510) chosen for their respective drive shapes.

## Database-on-btrfs CoW interaction

Two interactions to handle separately:

### Write-performance (`chattr +C` / `nodatacow`)

Database directories should have CoW disabled to avoid write amplification. For Immich's Postgres in `/var/lib/immich/database`, set the directory `+C` before initialization, or place service state on a subvolume mounted with `nodatacow`. This is a **performance fix, not backup-consistency**.

### Backup-consistency (logical dumps before backup)

Filesystem snapshot of a running database produces inconsistent state. Backup correctness requires a logical dump (`pg_dump` / SQLite `VACUUM INTO`) before restic touches the data. See `docs/reference/services.md` § Backup-correctness patterns.

## Filesystem context (`nori.fs`)

`nori.fs.<n>` is Reader-shaped — declared alongside the host's disko config; each entry pairs a path with a value tier (`re-derivable` | `user` | `service` | `irreplaceable`). Service modules read `config.nori.fs.<n>.path`; backup repo paths + btrbk subvolume lists derive from the tier filter.

Schema in `modules/infra/storage/default.nix`; declarations in `machines/workstation/disko*.nix`. Adding a media subvolume = one declaration; backup + snapshot wiring follows.

## Snapshot policy (btrbk)

`modules/infra/backup/btrbk.nix` declares two btrfs subvolume snapshot instances (root + media). Daily by default; retention follows the value-tier table above.

Both `restic-backups-*` and `btrbk-*` units get `OnFailure = [ "notify@%n.service" ]` so silent failures fire an ntfy alert.

## Backup destinations + retention

Dual local targets: `onetouch` (SFTP to aurora, off-chassis) + `mp510` (workstation NVMe). Cloud off-site explicitly rejected per `docs/decisions/0002-aurora-as-family-vault.md` — total-apartment loss is an accepted residual risk; the `nori.backupTargets` schema supports remote SFTP if that risk tolerance ever changes. Each service backed up to all configured targets simultaneously.

| Path / service | OneTouch + mp510 (local) |
|---|---|
| `/home` | Daily · keep 14d + 4w |
| `/srv/share` | Daily · keep 14d + 4w |
| Immich (dumps + uploads) | Daily · keep 7d + 4w |
| Open WebUI dump | Daily · keep 7d + 4w (paused — see roadmap) |
| Other service state | Daily · keep 7d |
| `@downloads` | Not backed up (re-derivable) |
| `@photos`, `@home-videos`, `@projects` | Daily · keep 14d + 4w |

## Backup verification

Three-cadence ladder + the live test recipe.

| Cadence | What | Action |
|---|---|---|
| Weekly | `restic check` | Metadata-only integrity scan |
| Monthly | `restic check --read-data-subset=10%` | Rolling sample; full repo covered ~every 10 months |
| Monthly | `restore-drill-services.service` | 17 service repos restored to `/var/restore-test/<svc>-<ts>/`, sha256-sample 20 files per repo. ~5 min wall |
| Quarterly | `restore-drill-user-data.service` | user-data tier restored (~99 GiB). ~30 min wall |
| Manual | `restore-drill-all.service` | All repos incl. `media-irreplaceable`. Multi-hour |
| Per-deploy | `just test-backups` | Runtime introspection: every unit's last snapshot ≤25h per target (see `docs/reference/runtime-tests.md`) |

All failures alert via ntfy. The drill is the **real RTO measurement**, not the static check green light. Drill split into per-tier services 2026-06-07 so a user-data failure no longer masks 17 GREEN service-tier results.

## Backup intent abstraction (`nori.backups`)

`nori.backups.<n>` (paths or skip + optional `tier`) drives every restic job. `tier` (`service` | `user` | `irreplaceable`) drives the default `pruneOpts` retention curve. The `every-service-has-backup-intent` flake check ensures no service module ships without declaring intent — either real paths or an explicit `.skip = "<reason>"`.

**Appliance hosts cannot use `paths`** — the role drives a placement assertion in `modules/infra/backup/default.nix` that fails eval if an appliance host (`nori.hosts.<self>.role = "appliance"`) declares a `paths`-based backup. Pi is an observer, not a state holder; daily restic writes to flash defeat its anti-write storage posture. Appliance-host services declare `.skip = "<reason>"` instead (or move the backup target to the workhorse via `nori.fs`).

The DynamicUser `StateDirectory` symlink-trap assertion derives from `config.systemd.services` introspection — self-maintaining. See `.claude/skills/gotcha-dynamicuser-statedirectory-symlink/`.

Schema in `modules/infra/backup/default.nix`. Cross-cutting infra (sops password, check timers) in `modules/infra/backup/restic.nix`. Each repo writes to **both** `/mnt/backup/<job>` (OneTouch ext4) **and** `/mnt/backup-local/<job>` (mp510 btrfs).
