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
| `ironwolf` | workstation: `repository = "/mnt/backup-local"` (IronWolf @restic-local subvol) | **Renamed to `mp510`**; workstation: `repository = "/mnt/backup-local"` (MP510 btrfs `@backup-local` subvol; data rsynced over from the IronWolf @restic-local subvol then the source dropped — see P14 ✓ landed below) |
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
| **P5** ✓ landed 2026-06-11 | `modules/effects/replication.nix` (`nori.replicas.<n>` registry + per-replica freshness verifier oneshot on the target host) + `just test-replicas` lever (composite-included). Empty registry smoke-passes (no units emitted, lever reports "no replicas declared"). Cross-host restic restore drill deferred to P11: workstation's `verify.nix` stays in place; the gate ungates per-service when state moves to aurora and aurora starts emitting its own restic units. | `nix flake check` green; `just test-replicas` exits 0 on empty registry ✓ |

### Stage 2 — Aurora bootstrap (no impact on workstation)

| Phase | What | Validation gate |
|---|---|---|
| **P6a** ✓ landed 2026-06-11 (Nix only) | Aurora HDD disko entry; `nori.fs` entries declaring `/mnt/family/*` paths on aurora | Aurora rebuilds; mount-units present but inert (`nofail`) until disko-apply |
| **P6b** ✓ 2026-06-11 | Format Toshiba HDD via `nix run github:nix-community/disko/latest -- --mode disko machines/aurora/disko-family.nix` | 932 GB family-vault btrfs; 6 subvols mounted at `/mnt/family/{photos,home-videos,projects,library,archive,.snapshots}`; 6.0M used (just FS overhead); empty + ready |
| **P7** *(reworked per ADR-0003)* | **Pi** gains Caddy + Authelia + Blocky-authoritative (shadow mode — workstation still primary). Pi's Caddy uses the full lan-route map via the P1b `runsOn` resolver; backends proxy to workstation today, aurora post-P8. | `dig @pi <X>.nori.lan` returns pi's LAN IP; `https://*.nori.lan` resolves via pi's Caddy to workstation backends; cert chain valid against pi's local CA after one-time per-device install |
| **P8** ✓ enables landed 2026-06-11 (`e76907b…4ca2254`) | Aurora gains family-tier service declarations with `enable = true` but pointing at empty `/var/lib/<svc>` and `/mnt/family/<X>`. Service inventory live on aurora with empty state: vaultwarden, radicale, calibre-web, komga, glance, heim, immich (full stack: server + ML + DB + redis), miniflux. navidrome deferred (path mismatch). `runsOn` still points at workstation per route — flip per-service as state migration completes (operator). Family clients continue to hit workstation. | All listed services active on aurora; loopback-only (binds + tailnet firewall land per-service during cutover); workstation continues to serve `*.home.phibkro.org` |

### Stage 3 — Data movement (irreversible without restore from backup)

| Phase | What | Validation gate |
|---|---|---|
| **P9** ✓ landed 2026-06-11 | Personal residue under `/Users/piplu` (24 GB Pictures/Takeout, CV, work folders, …) extracted by operator; MP510 wiped + reformatted as a single btrfs `mp510-backup` filesystem with 6 subvols (`@backup-local`, `@family-replica-{photos,home-videos,projects,library,archive}`). | MP510 mounted clean at all 6 final paths; 894 GB usable; `nix flake check` green ✓ |
| **P10** ✓ landed 2026-06-12 | Initial sync: workstation `@photos`/`@home-videos`/`@projects`/`@archive`/`@library` → aurora `/mnt/family/*` via rsync. home-videos + projects + archive landed on 2026-06-11. Photos retried after the `[[rsync-destination-service-ownership]]` trap (immich claimed `_immich-managed` mid-transfer); recovered by stopping aurora immich + chowning to `nori:users` + re-rsync (incremental). 220 GB photos + 48 GB music both on aurora as of 03:25 2026-06-12. Music retry needed `--rsync-path="sudo rsync"` because aurora's `nori` uid isn't in the `media` group that owns `/mnt/family/library/music`. | sha256 manifest match on both sides; pre-rsync restic snapshot intact. |
| **P11** ✓ landed 2026-06-12 | Per-service state migration. Same-shape "stop → dump → SFTP → restore → swap" cycle ran 11 times: vaultwarden (sqlite bellwether), glance + heim + radicale (stateless), miniflux (Postgres, surfaced the `--no-owner` ownership trap → `[[postgres-ownership-after-dump-restore]]` memory + `/restore-pg-with-owner-fix` skill), filmder + grafana (stateless), calibre-web + komga (no data dependency — library was empty on workstation too), navidrome (small sqlite — 6.4 MB DB migration preserved playlists + play counts + scrobble tokens; cache rebuilt on aurora), and **immich** (the big one — 79 MB pg_dump via runbook at `docs/runbooks/immich-cutover.md`, 14,164 assets + 1 user preserved; `_immich-managed` chowned back to immich:immich post-restore). Workstation closure shrank by ~447 MB after the immich teardown. | Service-by-service smoke tests + `{"res":"pong"}` end-to-end through pi's Caddy proxy. |
| **P12** ✓ landed 2026-06-12 (`0629326`) | Entry-plane flip from workstation to pi. `nori.lanIp` derives from pi in `modules/common/default.nix`; `authelia.runsOn` flips to pi; workstation `caddy.enable` + `authelia.enable` go false (closure -96 MB). Hermes had its own gate against non-loopback binds — landed via `--insecure` flag (operator-tier audience makes tailnet membership the auth perimeter; Host/Origin rewrite at Caddy preserves the GHSA-ppp5-vxwm-4cf7 mitigation for browser-DNS-rebinding). Tailscale admin UI DNS push order swapped to pi (operator-driven). Pi's `gatus.exposeViaCaddy = false` legacy override dropped; `modules/services/hermes.nix` moved into the services bundle so pi-as-Caddy-host sees the route. End-to-end verified from all four tailnet hosts (workstation, pi, aurora, pavilion) — 22 routes return 200/302/307 through pi. | All `https://*.<domain>` reachable through pi's Caddy ✓; workstation Caddy + Authelia disabled ✓. |
| **P13** ✓ landed 2026-06-11 (`e8a8813` + `c3ba27f` + tailscale-ssh-off runtime) | OneTouch physical move: unplug from workstation, plug into aurora; aurora's disko-onetouch entry takes over; restic target URL flips back to local-path on aurora; workstation's pointer flips to `sftp:` form | First restic snapshot end-to-end through aurora SFTP at 03:39 succeeded (vaultwarden-onetouch unit; snapshot + prune + repack ~6s). |
| **P14** ✓ landed 2026-06-11 | IronWolf `@restic-local` data (~57 GiB) rsynced to MP510 `@backup-local`; mount swap landed via nixos-rebuild; `@restic-local` dropped via `btrfs subvolume delete`. Restic target renamed `ironwolf` → `mp510` per the drive-based convention matching `onetouch`. Dropping the irreplaceable subvols from IronWolf is deferred until P10 photos finishes (confirmation that aurora has the data). | IronWolf free space recovered to 1.01 TiB; `/mnt/backup-local` now MP510-backed; first restic backup post-rename succeeded ✓ |

### Stage 4 — Replication + verification

| Phase | What | Validation gate |
|---|---|---|
| **P15** ✓ wired live 2026-06-12 (`2877267`); first full run in flight | btrfs send/receive timer aurora `/mnt/family/*` → workstation MP510 `/mnt/family-replica/*`. Both modules committed + live: aurora ssh key in sops (owner=btrbk:btrbk so the unit's User=btrbk can read it), workstation `users.users.btrbk.openssh.authorizedKeys.keys` carries the aurora pubkey. Per-subvol target shape (each `@family-replica-<X>` is its own mountpoint, no single shared parent btrfs filesystem). First-run started 16:21; full ~500 GB transfer takes hours, daily timer carries it home. Retention 7d/4w/6m. | First full receive completes for all 5 subvols ✓ (verify via `sudo btrfs subvolume list /mnt/family-replica` after first-run finishes). Subsequent runs incremental. P5 replication-consistency-verifier returns clean. |
| **P16** | Optional: pavilion weekly tertiary replica (subvol on pavilion HDD) | Same verifier, on a weekly cadence |
| **P17** | Hetzner Storage Box restic target | Restic check against Hetzner passes; backup snapshots present off-site |

### Stage 5 — Power optimization

| Phase | What | Validation gate |
|---|---|---|
| **P18** *(diagnose ✓ landed 2026-06-12 `93a18f8`; awaits operator reboot to verify)* | s2idle resume hang root cause: `hardware.nvidia.powerManagement.enable = false` meant NVIDIA's kernel module loaded without `NVreg_PreserveVideoMemoryAllocations=1` and `NVreg_UseKernelSuspendNotifiers=1` — VRAM contents weren't preserved across s2idle, compositor came back to undefined GPU state ("default background, no input"). Flipped `powerManagement.enable = true`; NixOS module now writes both params to `/etc/modprobe.d/nixos.conf`. **Reboot required** — kernel module params take effect at module load time. After reboot, `systemctl suspend` is the actual test. | Resume from `systemctl suspend` returns to lockscreen with working keyboard/mouse; hyprlock accepts the password and unlocks normally. |
| **P19** *(NIC config landed 2026-06-12 `54a39d8`; magic-packet test gated on P18 verification)* | Wake-on-LAN tested: pi or aurora sends magic packet, workstation wakes; Caddy/Samba/Jellyfin reachable post-wake. **Landed:** `Wake-on: g` (MagicPacket) on workstation's RTL8125 (enp42s0, MAC `2c:f0:5d:5d:f7:60`), via a boot oneshot in `hardware.nix` (scripted-networking doesn't process the .link file the `networking.interfaces.<n>.wakeOnLan` option emits — saved as `[[scripted-networking-link-files-inert]]` memory). End-to-end test: once P18 verified, suspend workstation, then from pi: `nix shell nixpkgs#wakeonlan -c wakeonlan -i 192.168.1.255 2c:f0:5d:5d:f7:60`. | <30s wake-to-service window |
| **P20** *(gated on P18+P19 verification)* | Workstation default sleep policy: re-add the 30-min suspend listener in `home/desktop/hypr-lock.nix` (was removed in `e12d34d` pending the P18 fix). Power-draw measurement vs the projected ~5 kWh/day savings baseline. **Do NOT re-enable hypridle auto-suspend until P18 reboot-verified** — risking a guaranteed hang at the next 30-min idle window is worse than the current always-on state. | Observed power draw drops to projected baseline (workstation idle ~0W when asleep, ~250W when awake). |

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
