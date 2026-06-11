# Aurora migration plan

> **Source of truth** for the workstation → aurora workload + storage redistribution. Every phase, every delta, every cutover lives here. Updated as the migration progresses.

**Goal:** Move the family-facing surface + irreplaceable data to aurora so workstation can sleep when no GPU/transcode/bulk-storage workload is active. Reach a 3-copy replication posture for irreplaceable media (4 copies once Hetzner lands).

**Path chosen:** B (see [target architecture](#target-architecture)) — `@photos`/`@home-videos`/`@projects`/`@library`/`@archive` + family-tier services to aurora; `@downloads` + Jellyfin + `*arr` stay on workstation. MP510 becomes workstation's local restic-local tier + the cold replica. OneTouch physically moves to aurora as the backup vault.

---

## Target architecture

| Host | Role | Power |
|---|---|---|
| **Pi** | Always-on network appliance (DNS, observability, alerting, Tailscale subnet+exit) | ~5W |
| **Aurora** | Always-on family/data host. Primary `/mnt/family/*`, Caddy + Authelia + Blocky-authoritative #1, family-tier services, Immich/Calibre/Komga/Navidrome, OneTouch backup vault | ~25-30W |
| **Workstation** | Sleep-friendly compute. Ollama, Jellyfin, `*arr`/qBittorrent/Stremio, `@downloads` (IronWolf), desktop. Cold replica of `/mnt/family/*` on MP510 | 0W asleep / ~250W on |
| **Pavilion** | Agent quarantine (hermes) + optional weekly tertiary irreplaceable-media replica | Scheduled |

Replication: aurora HDD (live) → workstation MP510 (cold replica, btrfs send/receive) → OneTouch (restic) → Hetzner (future restic). 3-2-1 met locally; off-site achieved when Hetzner lands.

---

## Delta — drives

| Drive | Current state | Destination state | Transformation | Reversibility |
|---|---|---|---|---|
| WD SN750 NVMe (workstation) | `/`, `/home`, `/var/lib`, `/srv` | Same | None | n/a |
| Force MP510 NVMe (workstation) | `/mnt/windows-ro` (NTFS Windows residue) | btrfs: `/mnt/backup-local` + `/mnt/family-replica/*` | Wipe + disko apply | **One-shot wipe** — extract any Windows data first |
| ST4000NE001 IronWolf (workstation USB) | `/mnt/media/{downloads,streaming,photos,home-videos,projects,archive,library}` + `/mnt/backup-local` (@restic-local subvol) | `/mnt/media/{downloads,streaming}` only | `btrfs subvol delete` for `@restic-local`, `@photos`, `@home-videos`, `@projects`, `@archive`, `@library` after data verified elsewhere | Subvol delete is permanent — only run after restic verifies the off-host copies |
| Seagate OneTouch (USB) | Attached to workstation, `/mnt/backup` (ext4) | Attached to aurora, `/mnt/backup` (ext4) | Unplug + plug into aurora | Plug back into workstation for rollback |
| Aurora LiteOn SSD | `/`, `/home`, `/nix` | Same + adds `/var/lib` carry-over for migrated services | Disko subvol additions | Reversible (subvols can be removed) |
| Aurora Toshiba HDD | Idle (declared in disko comments as future capacity) | btrfs: `/mnt/family/{photos,home-videos,projects,library,archive}` + service-state overflow | Disko apply | **One-shot format** |
| Pi USB FIT 128 GB | Pi root + state | Same | None | n/a |
| Pavilion WD WD6400BPVT 640 GB | Impermanence root + persist + nix | Same; optional weekly third-replica btrfs subvol | Subvol addition only if pavilion replica tier is opted in | Reversible |

---

## Delta — storage namespaces (`nori.fs.<X>`)

| Namespace | Current path / host | Destination path / host | Consumers (after) | Sync mechanism |
|---|---|---|---|---|
| `home` | workstation `/home` | unchanged | operator, restic | unchanged |
| `share` | workstation `/srv/share` | unchanged | Samba (workstation), family clients, restic | unchanged |
| `nori` | workstation `/srv/nori` | unchanged | operator | unchanged |
| `downloads` | workstation `/mnt/media/downloads` | unchanged | qBittorrent, `*arr`, Jellyfin | unchanged |
| `photos` | workstation `@photos` | **aurora `/mnt/family/photos`** | Immich, Samba (aurora), restic | rsync first sync, then btrfs send/receive nightly to workstation MP510 |
| `home-videos` | workstation `@home-videos` | **aurora `/mnt/family/home-videos`** | Samba (aurora), restic | same |
| `projects` | workstation `@projects` | **aurora `/mnt/family/projects`** | Samba (aurora), restic | same |
| `library` | workstation `@library` | **aurora `/mnt/family/library`** | Calibre-web, Komga, Navidrome, Samba (aurora), restic | same |
| `archive` | workstation `@archive` | **aurora `/mnt/family/archive`** | Samba (aurora), restic | same |
| `family-replica/{photos,…}` | (does not exist) | workstation MP510 `/mnt/family-replica/*` | btrfs receive endpoint, restic | btrfs receive nightly from aurora |

---

## Delta — services

Services pinned by GPU or bulk storage stay. Family-tier + photo/book/music readers move. Network appliance functions stay split (pi appliance / aurora authoritative pair).

| Service | Current host | Destination | State to migrate | Cutover style |
|---|---|---|---|---|
| **Stay on workstation** | | | | |
| Ollama | workstation | workstation | n/a | n/a |
| Open-WebUI | workstation | workstation | n/a | n/a |
| Jellyfin | workstation | workstation | n/a | n/a |
| qBittorrent | workstation | workstation | n/a | n/a |
| sonarr / radarr / lidarr / bazarr / prowlarr / jellyseerr / recyclarr | workstation | workstation | n/a | n/a |
| Stremio | workstation | workstation | n/a | n/a |
| Samba (`/mnt/media`, `/srv/share`, `/srv/nori`) | workstation | workstation | n/a (drives stay) | n/a |
| Hermes agent | workstation | (per ROADMAP → pavilion later) | out of scope here | n/a |
| Sunshine, gaming, Hyprland | workstation | workstation | n/a | n/a |
| **Move to aurora** | | | | |
| Caddy | workstation | aurora | Authelia client config + sops template | Parallel stand-up; flip `nori.lanIp` derivation; old Caddy retires |
| Authelia | workstation | aurora | sops secrets (clients + hash material) carry over via `sops updatekeys`; session store is ephemeral | Stop on workstation after aurora stands up — open OIDC sessions invalidate (re-login required) |
| Blocky-authoritative #1 | workstation | aurora | stateless (config-derived) | Parallel; flip Tailscale DNS push to list aurora before workstation |
| Vaultwarden | workstation | aurora | SQLite vault + attachments | Stop, sqlite3 `.backup`, sftp to aurora, restore, start; one-shot ~minutes downtime |
| Radicale | workstation | aurora | SQLite collections + htpasswd | Same shape as Vaultwarden |
| Miniflux | workstation | aurora | Postgres (pg_dump → pg_restore) | Same shape; longer dump for users with many feeds |
| Glance | workstation | aurora | stateless | Just declare on aurora |
| Heim | workstation | aurora | stateless | Same |
| Immich (server + DB + ML) | workstation server / aurora ML | aurora (all) | Postgres + VectorChord + Redis state + originals from `@photos` (via the data move) | Stop server, dump DB, originals rsync to `/mnt/family/photos`, restore DB on aurora, repoint `IMMICH_UPLOAD_LOCATION` to `/mnt/family/photos`, restart |
| Calibre-web | workstation | aurora | SQLite library + cache | Dump + restore; repoint to `/mnt/family/library` |
| Komga | workstation | aurora | SQLite + thumbnails | Same |
| Navidrome | workstation | aurora | SQLite + index cache | Same; repoint to `/mnt/family/library/music` |
| Samba (`/mnt/family/*`) | (does not exist) | aurora | new shares | Follows the drive — declared via per-drive samba schema (P4) |
| **Network appliance (split)** | | | | |
| Blocky-secondary | pi (forwarder) | pi (self-hosted after route data extraction lands) | n/a | Configuration flip |
| Gatus (station-side) | workstation | aurora | stateless (config-derived) | Reconfig |
| **Unchanged on pi** | | | | |
| VictoriaMetrics, VictoriaLogs, Beszel hub, ntfy server, heartbeat, Tailscale subnet+exit | pi | pi | n/a | n/a |
| **Per-host instance** | | | | |
| node-exporter, process-exporter, nvidia-gpu-exporter | per-host | per-host (aurora gains them already; workstation, pavilion already have them) | n/a | n/a |
| Beszel agent | per-host | per-host | n/a | n/a |
| restic schedulers + btrbk | workstation | per-host (each host pushes its own data) | new schedulers on aurora | additive |

---

## Delta — backup targets (`nori.backupTargets`)

| Target | Current shape | Destination shape |
|---|---|---|
| `onetouch` | workstation: `repository = "/mnt/backup"` (local ext4) | aurora: `repository = "/mnt/backup"` (local ext4, same drive moved physically); workstation: `repository = "sftp:restic@aurora.saola-matrix.ts.net:/mnt/backup"` (remote SFTP) |
| `ironwolf` | workstation: `repository = "/mnt/backup-local"` (IronWolf @restic-local subvol) | **Renamed to `local-fast`**; workstation: `repository = "/mnt/backup-local"` (MP510 btrfs); aurora may declare its own `local-fast` on the HDD if local-restic-mirror tier wanted there too |
| `hetzner` | n/a (ROADMAP item) | Future: workstation + aurora both declare `repository = "sftp:uXXXXX@uXXXXX.your-storagebox.de:23/restic"` |

---

## Delta — `nori.lanRoutes` upstreams

After Phase 1 (pool support in the lan-route schema), routes name their host(s) explicitly. Routes that change destination:

| Route | Current upstream | Destination upstream |
|---|---|---|
| `vault.nori.lan` (Vaultwarden) | workstation | aurora |
| `caldav.nori.lan` (Radicale) | workstation | aurora |
| `rss.nori.lan` (Miniflux) | workstation | aurora |
| `photos.nori.lan` (Immich) | workstation | aurora |
| `books.nori.lan` (Calibre-web) | workstation | aurora |
| `comics.nori.lan` (Komga) | workstation | aurora |
| `music.nori.lan` (Navidrome) | workstation | aurora |
| `home.nori.lan` (Glance) | workstation | aurora (Phase 2 makes this a pool: `[ aurora, workstation ]`) |
| `heim.nori.lan` | workstation | aurora |
| `auth.nori.lan` (Authelia) | workstation | aurora |
| Routes with no change | | |
| `media.nori.lan` (Jellyfin) | workstation | workstation |
| `chat.nori.lan` (Open-WebUI) | workstation | workstation |
| `arr.nori.lan` (jellyseerr), `torrents.nori.lan` (qBit), `stream.nori.lan` (Sunshine), `hermes.nori.lan` | workstation | workstation |
| `status.nori.lan` (Gatus), `metrics.nori.lan` (Beszel), `alert.nori.lan` (ntfy), `logs.nori.lan` (VictoriaLogs), `tsdb.nori.lan` (VictoriaMetrics) | pi | pi |

---

## Delta — abstractions / refactors

| Abstraction | Type | Owner phase |
|---|---|---|
| `nori.services.<svc>.{enable,tags,enableByTag}` | New effect module (`service-placement.nix`) | P1 |
| `nori.lanRoutes.<X>.port` auto-assignment (sequential aggregator, manual pins preserved) | Schema extension | P1 |
| `nori.lanRoutes.<X>.upstreams` (host pool support) | Schema extension | P1 |
| Service module sweep (every `modules/services/*.nix` wrapped in `mkMerge` + `mkIf cfg.enable`) | Mechanical refactor | P2 |
| Per-host `nori.services.*.enable` declarations | Configuration | P3 |
| `nori.fs.<X>.samba` block (Samba export follows the drive) | Schema extension | P4 |
| Replication-consistency-verifier module + `just test-replicas` recipe | New runtime test | P5 |
| Cross-host restic restore drill | New runtime test | P5 |

---

## Phase ordering

Each phase ends in a working system. Validation gate at the end of each must pass before the next begins.

### Stage 1 — Foundation (autonomous-tractable, no behavior change)

| Phase | What | Validation gate |
|---|---|---|
| **P1** ✓ landed 2026-06-11 (`eceee10`) | `service-placement.nix` effect module — `nori.services.<svc>.{enable,tags,enabled}` + `nori.enableServicesByTag`. Schema only; no consumers yet. | `nix flake check` green; workstation `system.build.toplevel.drvPath` identical before/after |
| **P1b** *(deferred to P12)* | `nori.lanRoutes.<X>.upstreams` host-pool field + Caddy generator change | Lands with P12 cutover where it's actually consumed |
| **P1c** *(deferred — not blocking)* | lan-route port auto-assignment (sequential aggregator) | Defer until a route actually needs auto-port (today every route pins explicitly) |
| **P2** | Service module sweep: wrap each `modules/services/*.nix` in the gated-activation shape; assign `tags` per module; default `enable = false`; the wrap is mechanical | `nix-diff` per host = empty (semantic-equivalence) |
| **P3** | Host opt-in: `machines/<host>/default.nix` declares its current activation set via `nori.services.*.enable = true` or `enableByTag = [...]`. Workstation reproduces today's set exactly. | `nix-diff` per host = empty |
| **P4** | `nori.fs.<X>.samba` block + generator emitting Samba shares from per-fs declarations | `just test-samba` (new lever) passes on workstation with current shares |
| **P5** | Replication-consistency-verifier + cross-host restore drill modules | Both invokable but no replica targets defined yet; smoke-test passes by detecting "no replica configured" cleanly |

### Stage 2 — Aurora bootstrap (no impact on workstation)

| Phase | What | Validation gate |
|---|---|---|
| **P6** | Aurora HDD disko entry; `nori.fs` entries declaring `/mnt/family/*` paths on aurora (but no data in them yet) | Aurora rebuilds; mounts present; empty |
| **P7** | Aurora gains Caddy + Authelia + Blocky-authoritative-#1 (shadow mode — workstation still primary, aurora returns the same map but Tailscale DNS push hasn't been updated yet) | `dig @aurora <X>.nori.lan` returns workstation IP for all known routes; `https://*.nori.lan` still served by workstation |
| **P8** | Aurora gains family-tier service declarations with `enable = true` but pointing at empty `/var/lib/<svc>` and `/mnt/family/<X>` (services start, DBs initialize empty) | Services up; UIs reachable directly via aurora's tailnet IP on internal ports; no data |

### Stage 3 — Data movement (irreversible without restore from backup)

| Phase | What | Validation gate |
|---|---|---|
| **P9** | Extract Windows data from MP510 (last call), wipe MP510, apply new disko → `/mnt/backup-local` + `/mnt/family-replica/*` mountpoints | MP510 mounted clean; sufficient space |
| **P10** | Initial sync: workstation `@photos`/`@home-videos`/`@projects`/`@library`/`@archive` → aurora `/mnt/family/*` via rsync (one-shot, ~334 GB over LAN — ~hours) | sha256 manifest match on both sides; restic snapshot of source taken just before the move (rollback path) |
| **P11** | Service state migration (Vaultwarden, Radicale, Miniflux, Immich, Calibre-web, Komga, Navidrome): dump on workstation, sftp to aurora, restore into running services | Service-by-service smoke test (UI reachable, data visible, sample operations work) |
| **P12** | Cutover: Caddy routes flip to aurora upstreams; Tailscale DNS push order swaps (aurora primary); Authelia URLs re-issue OIDC tokens; family clients re-login | All `https://*.nori.lan` reachable; old workstation Caddy disabled |
| **P13** | OneTouch physical move: unplug from workstation, plug into aurora; aurora's disko-onetouch entry takes over; restic target URL flips back to local-path on aurora; workstation's pointer flips to `sftp:` form | Restic snapshots from workstation reach aurora over SFTP; restic snapshots from aurora succeed locally |
| **P14** | Drop `@restic-local` subvol from IronWolf; drop irreplaceable subvols from IronWolf | IronWolf now contains only `@downloads` + `@streaming`; sufficient space recovered |

### Stage 4 — Replication + verification

| Phase | What | Validation gate |
|---|---|---|
| **P15** | btrfs send/receive timer aurora `/mnt/family/*` → workstation MP510 `/mnt/family-replica/*` | First receive completes; subsequent runs are incremental; replication-consistency-verifier (P5) returns clean |
| **P16** | Optional: pavilion weekly tertiary replica (subvol on pavilion HDD) | Same verifier, on a weekly cadence |
| **P17** | Hetzner Storage Box restic target | Restic check against Hetzner passes; backup snapshots present off-site |

### Stage 5 — Power optimization

| Phase | What | Validation gate |
|---|---|---|
| **P18** | hypridle suspend re-enabled (after the lockscreen resume bug is fixed) | Resume from suspend works; no lockscreen lockout |
| **P19** | Wake-on-LAN tested: aurora sends magic packet, workstation wakes; Caddy/Samba/Jellyfin reachable post-wake | <30s wake-to-service window |
| **P20** | Workstation default sleep policy: idle suspend after configurable window; WoL from aurora handles on-demand wake | Observed power draw matches the calculated baseline |

---

## Reversibility ladder

| Operation | Reversible? | Recovery path |
|---|---|---|
| P1–P8 (Nix-only edits, no data movement) | Yes — `git revert` | Single command |
| P9 (MP510 wipe) | **No** | Pre-wipe Windows data extraction. Drive replaceable but data is gone. |
| P10 (initial sync to aurora) | Yes during sync | Source intact until P14; rollback = stop using aurora copy, redirect services back |
| P11 (service state migration) | Yes per service | Restore workstation copy from restic snapshot taken in P10 |
| P12 (route cutover) | Yes — `git revert` | Caddy flips back to workstation upstreams |
| P13 (OneTouch physical move) | Yes (re-plug into workstation) | Restic target URLs flip back |
| P14 (IronWolf subvol delete) | **No** | Pre-delete restic snapshot covers everything; restore path = restic restore |
| P15 (replication startup) | Yes | Replica is additive; deleting it doesn't affect primary |
| P17 (Hetzner add) | Yes | Just a new target; nothing depends on it yet |
| P18–P20 (power tuning) | Yes | Config-only |

---

## Resolved decisions

(Recorded inline against the architecture in ADR-0002.)

- **Pavilion as tertiary replica — yes.** Weekly btrfs send/receive from aurora; ~334 GB on pavilion's 640 GB drive. Three host-level copies before counting the OneTouch restic vault.
- **No Hetzner / cloud off-site.** Three host-level copies + restic vault cover every single-component failure mode. Total-apartment loss accepted as residual risk. The `nori.backupTargets` schema supports remote SFTP if this decision is reversed later.
- **MP510 dual-role.** `/mnt/backup-local` (workstation-side restic-local target) + `/mnt/family-replica/*` (cold replica). 894 GB easily covers both with headroom.
- **Filmder out of scope.** Already moved.

## Still open

- **Aurora SSD vs HDD for service state.** Postgres (Immich + small DBs) ~50 GB. SSD (119 GB, ~10 GB used by root) has space but is tight; HDD has slower fsync for DB workloads. Probably SSD for DB, HDD for media — worth measuring on first migration target (Vaultwarden is the smallest; use it as the bellwether).
- **Samba bookmark migration.** Family devices have `smb://workstation/photos` etc. After P12 the family-tier shares are on aurora. Strategy: keep workstation Samba serving `share`/`nori`/`downloads`; introduce aurora Samba for `family/*`; family devices add aurora bookmarks (existing workstation bookmarks for media/downloads keep working). Additions only, no deletions. Family briefing needed before P12.

---

## References

- `docs/decisions/0002-aurora-as-family-vault.md` — the *why* and the alternatives consciously rejected
- `docs/STORAGE.md` § value tiers, backup destinations
- `docs/TOPOLOGY.md` § service placement
- `docs/ROADMAP.md` § Lower-priority appliance candidates
- `modules/effects/backup.nix` — `nori.backupTargets` schema (remote-URL support landed 2026-06-10)
- `modules/effects/fs.nix` — `nori.fs` schema (extension for `samba` block lands in P4)
- `modules/effects/lan-route.nix` — `nori.lanRoutes` (extensions for `port` aggregator + `upstreams` land in P1)
