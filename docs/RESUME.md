# Resumption guide

You are an agent continuing the nori homelab buildout. Phase 4
(bare-metal NixOS install on nori-station) just finished. This doc is
the orientation brief — read it first, then `docs/DESIGN.md` for
canonical architecture.

## Where state lives

- **Repo:** `/Users/nori/Documents/nix-migration` (local), pushed to
  `git@github.com:phibkro/homelab` (public, `main`).
- **Canonical design:** `docs/DESIGN.md`. Two-host topology
  (nori-station + nori-pi), seven-layer architecture, three named
  backup patterns (A/B/C), disko-from-day-zero. Source of truth for
  *why* decisions are what they are.
- **Project memory** (auto-loaded when working in this directory):
  `~/.claude/projects/-Users-nori-Documents-nix-migration/`. Index is
  `MEMORY.md`; files cover user, project state, gotchas, working style.
- **Git history:** `git log --oneline` — commit-by-commit narrative.
- **Inventory** (gitignored): `inventory-nori-station-20260424T220429Z/`
  captures Ubuntu source. Use selectively when migrating specific
  services in Phase 5.

## Phase status

| Phase | What | State |
|---|---|---|
| 0 | Inventory + flake skeleton | done |
| 1 | Backups (rsync + partclone) | done; verified on One Touch |
| 2 | Reformat IronWolf Pro to btrfs | **DONE** (pulled forward; see below) |
| 3 | VM dry-run install | done; `vm-test` retained for testing |
| 4 | Bare-metal install on nori-station | done |
| 5 | Service migration | in progress (file/AI/media services live; Cloudflare/observability pending) |
| 6 | Desktop environment (Hyprland) | done — greetd + Hyprland + waybar + mako + hyprlock + hypridle live; bind layer derives Hyprland config + cheatsheet from one record list |

Reactive (no scheduled trigger): Cloudflare Tunnel + Access, email
digest reports, second media drive, deploy-rs. See DESIGN.md.

## Current state of nori-station

NixOS on bare metal. Reachable from the Mac at `192.168.1.181` (LAN)
and on the tailnet at canonical `nori-station` (renamed from
`nori-station-1` after deleting the offline Ubuntu ghost). User
`nori` with passwordless wheel sudo, TTY password set manually
post-install. SSH key-only.

`modules/common/{base,users,tailscale}.nix` plus `default.nix` is the
new shape per DESIGN.md L335-348; `hosts/common.nix` is gone. The
tailscale module is the first service module — declares
`extraUpFlags = [ "--ssh" "--hostname=${networking.hostName}" ]` so
any future re-auth lands the canonical hostname.

`disko` applied to both NVMe root (SN750, btrfs label `nixos`, six
subvolumes) and IronWolf media (4 TB, btrfs label `ironwolf-storage`, five
subvolumes per DESIGN L130-138). Both disko configs target by-id
paths, not `/dev/nvme*` — see "Disk identity" below.

Media tree current state:

```
/mnt/media/home-videos  18 GB  partial OneTouch Footage transfer
/mnt/media/photos       53 GB  IronWolf memories + partial OneTouch memories
/mnt/media/projects     18 GB  IronWolf projects + _exports/ subdir
/mnt/media/streaming     0     intentional, re-derivable per DESIGN tier
```

Files under `/mnt/media/` are owned `nori:users`. The OneTouch
contributions in `home-videos` and `photos` are mid-migration leftovers
the user wanted to review later (the OneTouch is the backup, doesn't
strictly need to live on the IronWolf too); not load-bearing.

## Disk identity (read this before anything that touches `/dev/nvmeN`)

NVMe `/dev` enumeration is unstable across reboots. At install time,
`/dev/nvme0n1` was the SN750; post-reboot it's `/dev/nvme1n1`. The
disko configs are by-id-pinned to prevent accidentally targeting the
wrong drive. Always disambiguate by model:

- WD Black SN750 1TB → NixOS root, btrfs label `nixos`
  by-id `nvme-WDS100T3X0C-00SJG0_204526810532`
- Corsair Force MP510 960GB → Windows, **never touch**
  by-id `nvme-Force_MP510_2031826300012953207B`
- Seagate IronWolf Pro 4TB → media btrfs, label `ironwolf-storage`
  by-id `ata-ST4000NE001-2MA101_WS24X543`
- Seagate One Touch 5TB → external backup drive, exfat, normally on
  the Mac at `/Volumes/One Touch`. UUID `2A05-DC62`.

## Active services (snapshot)

All HTTP services exposed via Caddy at `https://<name>.nori.lan`. Direct backend ports are closed on tailnet (default-deny via `nori.lanRoutes`); Caddy on `:80 + :443` is the only entry point. Samba bypasses Caddy on `:445` (not HTTP).

| URL | Module | Backend port | Notes |
|---|---|---|---|
| `https://auth.nori.lan` | `authelia.nix` | 9091 | OIDC issuer; serves SSO for `chat` and `metrics` |
| `https://chat.nori.lan` | `open-webui.nix` | 8080 | Open WebUI; OIDC SSO via Authelia working end-to-end |
| `https://ai.nori.lan` | `ollama.nix` | 11434 | `pkgs.ollama-cuda`, RTX 5060 Ti |
| `https://media.nori.lan` | `jellyfin.nix` | 8096 | Jellyfin |
| `https://metrics.nori.lan` | `beszel.nix` | 8090 | beszel hub; OIDC client registered, Beszel-side config still pending |
| `https://status.nori.lan` | `gatus.nix` | 8082 | Gatus dashboard (no self-monitor) |
| `https://alert.nori.lan` | `ntfy.nix` | 8081 | local ntfy (also pushes to ntfy.sh for phone alerts) |
| `https://tv.nori.lan` | `sonarr.nix` | 8989 | Sonarr — TV management; first-run wizard pending |
| `https://movies.nori.lan` | `radarr.nix` | 7878 | Radarr — movie management; first-run wizard pending |
| `https://indexers.nori.lan` | `prowlarr.nix` | 9696 | Prowlarr — indexer aggregator; configure first, link Sonarr/Radarr after |
| `https://subtitles.nori.lan` | `bazarr.nix` | 6767 | Bazarr — subtitle automation; depends on Sonarr+Radarr |
| `https://requests.nori.lan` | `jellyseerr.nix` | 5055 | Jellyseerr — family request UI; tie to Jellyfin auth on first-run |
| `https://downloads.nori.lan` | `qbittorrent.nix` | 8083 | qBittorrent WebUI (port remapped from default 8080 to avoid open-webui collision) |
| `https://music.nori.lan` | `lidarr.nix` | 8686 | Lidarr — music management; library on @streaming/music; playback via Jellyfin |
| `https://books.nori.lan` | `calibre-web.nix` | 8084 | calibre-web — ebook UI + OPDS at /opds; library on @library/books; port remapped from 8083 |
| `https://comics.nori.lan` | `komga.nix` | 8085 | Komga — comics/manga server + OPDS at /api/v1/opds/v2; library on @library/comics; port remapped from 8080 |
| `smb://nori-station.saola-matrix.ts.net` | `samba.nix` | 445 | `/mnt/media` + `/srv/share`, single user `nori` |

Background workers / non-routed:
- `blocky.nix` — DNS adblock on `:53` LAN-wide via Tailscale DNS push (`100.81.5.122`)
- `backup-restic.nix` — three restic jobs (user-data, media-irreplaceable, open-webui Pattern C2) + weekly + monthly `restic check` timers, daily, sops password, real repo at `/mnt/backup/` (OneTouch ext4)
- `btrbk.nix` — daily root + media btrfs snapshots; `@archive` + `@library` included
- `ntfy.nix` (local) — backs the `notify@` template; OnFailure for restic + btrbk + restic-check routes through it
- `caddy.nix` — reverse proxy + internal CA, root cert in `modules/services/caddy-local-ca.crt` (committed) + system trust via `security.pki.certificateFiles`
- `arr-shared.nix` — `media` group + tmpfiles for shared library + download paths under `/mnt/media/streaming` and `/mnt/media/library`

Cross-cutting abstractions:
- `modules/lib/lan-route.nix` — single declaration per service generates Caddy vhost + Blocky DNS + Gatus monitor (+ optional tailnet firewall opening). Schema-validated. See `docs/CONVENTIONS.md`.
- `modules/services/groups.nix` — composable, non-exclusive aliases (ai, arr, media, observability, backup, networking, auth). Hosts compose via `imports = [...] ++ groups.<name> ++ ...`. Files stay flat under `modules/services/<service>.nix`; a service can belong to multiple groups.

Dev workflow:
- `Justfile` at repo root — `just` (default = rebuild), `just status`, `just logs <unit>`, `just check`, `just deploy` (git-based, no rsync), `just rollback`, etc. All recipes accept an optional `host` arg defaulting to `nori-station`. See `just --list`.
- `nh os switch` is the rebuild engine (replaces `nixos-rebuild` directly). Internal sudo escalation; nicer ADDED/REMOVED/CHANGED diff output.

## Loose ends to address opportunistically

1. ~~**Restic target — OneTouch transition in flight.**~~ DONE.
   OneTouch is now the local restic repo at `/mnt/backup` (ext4 via
   `disko-onetouch.nix`); user-data + open-webui repos verified clean
   with `restic check`. The 322 GB media-irreplaceable initial backup
   was running at last session-wrap (~75% complete). Hetzner Storage
   Box (off-site) remains on the roadmap as a second repository per
   DESIGN's local + off-site split.
2. **`common-cpu-amd-pstate`** not imported in `hosts/nori-station/hardware.nix`.
   Add back if AMD pstate tuning matters.
3. ~~**OneTouch leftovers in `/mnt/media/{home-videos,photos}`**~~ —
   resolved as part of the OneTouch → restic-target transition (item 1).
   Unique OneTouch data (memories, projects, legacy machine backups)
   has been migrated to the matching IronWolf subvolumes
   (`@photos`, `@projects`, the new `@archive`).
4. **`scripts/backup.sh`** has no restore-time verification. Pre-Phase-5
   rsync-to-exfat backups are snapshots-of-intent. Phase 5+ uses restic.
5. **Open WebUI: OpenRouter as second backend.** Deferred. Add
   `OPENAI_API_BASE_URL=https://openrouter.ai/api/v1` plus
   `OPENAI_API_KEY` from sops to enable cloud LLMs alongside Ollama.
6. **Jellyfin library config.** First-connect admin wizard at
   `https://media.nori.lan` — pick admin credentials, add
   `/mnt/media/home-videos` library (Stremio handles streaming
   entertainment, Jellyfin focuses on home videos).
7. **Beszel SSO consumer config.** Authelia-side OIDC client
   `metrics` is registered. Beszel-side: configure via PocketBase
   admin (`https://metrics.nori.lan/_/`) → Collections → users →
   ⚙ Options → OAuth2. Auto-gen for OIDC client setup deferred (would
   need lan-route extension + sops template plumbing).
8. **OIDC for other services.** Pattern proven for two services
   (chat, metrics-pending). Repeat per service that needs SSO. When
   N reaches 3-4, the auto-gen abstraction earns its keep.
9. **Media stack first-run wizards.** Twelve services live but un-configured
   (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Jellyseerr, qBittorrent,
   calibre-web, Komga, Immich, Radicale, Syncthing). Each has a one-time
   web-UI wizard. Order matters:
   Prowlarr first (configure indexers), then qBittorrent (set save paths +
   credentials), then Sonarr+Radarr+Lidarr (connect to both, add libraries
   under `/mnt/media/streaming/{shows,movies,music}`), then Bazarr (link
   Sonarr+Radarr), then Jellyseerr (tie to Jellyfin auth + connect
   Sonarr+Radarr). calibre-web + Komga + Immich are independent of the
   *arr chain — first-user creation + library path. Each module's header
   comment has the per-service wizard steps. ~60 min total.

   **Immich-specific wizard step worth flagging**: Settings →
   Administration → Backup → enable Scheduled Database Backup
   (Pattern B per DESIGN.md L283-289). Without it, Immich never
   writes the `.sql.gz` dumps that restic's media-irreplaceable
   path `/var/lib/immich/backups` is configured to pick up — so
   the photos themselves are backed up but the DB (with all your
   face-tags, albums, smart-search embeddings) isn't recoverable
   from restic until this is enabled. Cron `0 02 * * *`, keep 7.
10. **calibre-web nixpkgs overlay.** Module enables an inline overlay
    relaxing `requests` version pin (upstream pins `<2.33.0`, nixpkgs
    ships 2.33.1). Drop the overlay when nixpkgs catches up. See
    `modules/services/calibre-web.nix` for the override block.
11. **calibre-web bootstrap SIGSYS.** First-start `calibredb` call
    coredumps with signal 31 (bad system call) — almost certainly
    NixOS systemd hardening blocking a syscall calibre uses internally.
    The `metadata.db` gets created anyway and the service runs fine; if
    the noise bothers, add a `SystemCallFilter` allowlist override to
    the calibre-web service config.
12. **UWSM session validation.** `programs.hyprland.withUWSM = true` +
    greetd `uwsm start hyprland-uwsm.desktop` shipped (commits b48f1c2 +
    fc2ed4e). The currently-running Hyprland was started under the old
    direct-exec command, so the "Hyprland started without systemd
    integration" warning still shows. Logging out (SUPER+SHIFT+E) and
    back in via tuigreet picks up the UWSM-wrapped path. Once that's
    verified, expect the manual `systemctl --user restart waybar mako
    hypridle` dance to be unnecessary on session start.
13. **Vaultwarden self-hosted server.** Deferred. When ready: sops-managed
    admin token, repo lives at `/var/lib/vaultwarden` (folded into
    `user-data` restic + Pattern C2 SQLite `.backup` for correctness),
    lan-route at `vault.nori.lan`, Bitwarden Electron client (already
    installed) points at the self-hosted URL. Migration from cloud
    Bitwarden is one-time export → import → verify → sunset.
14. **Stremio.** Not in nixpkgs. Decision: use `web.stremio.com` in zen.
    Skip native install unless flatpak/AppImage becomes worth it.

## Conventions + how to make changes

See `docs/CONVENTIONS.md` for:
- Service module template (FS hardening, lan-route declaration, sops integration)
- Default-deny network + filesystem policy
- sops env-file format gotcha
- DynamicUser caveats + SupplementaryGroups=keys pattern
- Authelia OIDC client manual workflow

See `docs/gotchas.md` for landmines (NVMe enumeration, Caddy CA + Python certifi, openrsync, sops indentation, etc.).

## What's next

DESIGN.md L186-289 has the full table. Likely candidates in priority order:

1. **Real restic target.** Either PiOS-imperative restic-rest-server
   on the existing Pi (interim) or wait for a NixOS-bootable USB SSD
   to land `hosts/nori-pi/` declaratively. Then Hetzner Storage Box
   for off-site.
2. **Observability.** `services.beszel.{hub,agent}` for metrics,
   Uptime Kuma container for synthetic checks, ntfy for alerts. All
   per DESIGN L454-483.
3. **Immich.** Photo library; Pattern B backup (Immich's own dump).
   `/mnt/media/photos` becomes a raw archive that gets selectively
   imported into Immich's library (separate fs path under
   `/var/lib/immich/`).
4. **Cloudflare Tunnel + Access.** Reactive — only when Tailscale
   friction emerges (someone refuses to install another app, public
   sharing needed).
5. **Hyprland desktop.** Phase 6, done. Wallpaper deferred until an image is picked; everything else (greetd, waybar, mako, hyprlock, hypridle, audio fix, cheatsheet) is live and committed.

**`nori-pi` deferred** — no NixOS-bootable USB SSD on hand yet.
Existing Pi runs PiOS, can fill DNS (Blocky via apt) and/or
restic-target imperatively in the interim. Migrate to
`hosts/nori-pi/` declaratively when the SSD lands.

## Conventions

**Default-deny filesystem access for service modules.** Every new
service module's `serviceConfig` should include the namespace
restriction below; explicitly opt back in with `BindReadOnlyPaths`
for any host paths the service genuinely needs:

```nix
systemd.services.<name>.serviceConfig = {
  ProtectHome = lib.mkForce true;
  TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
  BindReadOnlyPaths = [ /* "/mnt/media", "/srv/share", etc. */ ];
};
```

`mkForce` is needed when the upstream module already sets
`ProtectHome` (ollama does), to avoid the boolean-vs-string
definition collision. Verify the namespace via:
`sudo nsenter -t <pid> -m -U -- ls /mnt/` from the host.

This mirrors the network policy (default-deny, services opt in to
specific tailnet/LAN ports). Goal: a compromised service can't
browse the host filesystem looking for credentials, even if it can
exec shell commands.

## Pending one-shot user actions

- Connect Mac/devices to Open WebUI (`http://nori-station.saola-matrix.ts.net:8080`)
  and verify chat history loaded correctly in the UI.
- Walk through Jellyfin admin wizard at `:8096` and add the two
  library paths.

## Working style with this user

`memory/feedback_style.md`. Short: answer first, push back on weak
decisions, don't manufacture concerns, don't flatter. Call out XY
problems. CS student with FP background; technical fluency assumed.

## On first turn

If the user's opening is open-ended ("where are we?", "what now?"),
respond with one paragraph of status, the immediate next concrete
action they'd take, and at most two open questions. Don't dump the
roadmap. They're already the architect; you're implementing alongside.
