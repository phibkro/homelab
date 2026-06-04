---
summary: Service catalog (what's deployed, on which host, via which module),
  the three backup-correctness patterns (A/B/C), observability + alert plane,
  monitored conditions and alert delivery. The "what's running" reference.
---

# Services

Native NixOS modules first, containers as fallback, no orchestration layer. The catalog below is what's deployed today; placement and naming follow the topology + audience models in `TOPOLOGY.md` + `NETWORK.md`.

## Catalog

Verified on `nixos-26.05`.

| Service | Module | Host | Route / exposure |
|---|---|---|---|
| **Streaming & media** | | | |
| Jellyfin | `services.jellyfin` | workstation | `media.nori.lan` (family) |
| Samba | `services.samba` | workstation | Tailnet 445, scoped to `/mnt/media`, `/srv/share` |
| Immich | `services.immich` (VectorChord, Postgres 17) | workstation | `photos.nori.lan` (family) |
| **AI & chat** | | | |
| Ollama | `services.ollama` (CUDA) | workstation | `ai.nori.lan` (operator) |
| Open WebUI | `services.open-webui` | workstation | `chat.nori.lan` (family) |
| **\*arr stack** | | | |
| Sonarr / Radarr / Lidarr | `services.{sonarr,radarr,lidarr}` | workstation | `tv` / `movies` / `music` `.nori.lan` (operator) |
| Prowlarr | `services.prowlarr` | workstation | `indexers.nori.lan` (operator) |
| Bazarr | `services.bazarr` | workstation | `subtitles.nori.lan` (operator) |
| Jellyseerr | `services.jellyseerr` | workstation | `requests.nori.lan` (family) |
| qBittorrent | `services.qbittorrent` | workstation | `downloads.nori.lan` (operator); webuiPort=8083 (8080 collides with Open WebUI) |
| **Books, comics, dashboard** | | | |
| calibre-web | `services.calibre-web` | workstation | `books.nori.lan` (family); ebook + OPDS; port 8084 |
| Komga | `services.komga` | workstation | `comics.nori.lan` (family); comics/manga + OPDS; port 8085 |
| Miniflux | `services.miniflux` | workstation | `news.nori.lan` (family); RSS reader; port 8087; shares system Postgres |
| Glance | `services.glance` | workstation | `home.nori.lan` (public); dashboard; port 8086 |
| **PIM** | | | |
| Radicale | `services.radicale` | workstation | `calendar.nori.lan` (family); CalDAV + CardDAV; htpasswd |
| Syncthing | `services.syncthing` | workstation | `sync.nori.lan` (operator); peer port 22000 open on tailscale0 |
| **Entry plane & SSO** | | | |
| Caddy | `services.caddy` | workstation | Tailnet TLS terminator + reverse proxy |
| Authelia | `services.authelia.instances.<name>` | workstation | `auth.nori.lan` (public); OIDC issuer for SSO |
| **DNS, observability, alerting** | | | |
| Blocky (forwarder) | `services.blocky` (`nori.blocky.role = "forwarder"`) | pi | LAN via tailnet DNS push |
| Blocky (self-hosted) | `services.blocky` (`nori.blocky.role = "self-hosted"`) | workstation | LAN fallback |
| Beszel hub | `services.beszel.hub` | pi | `metrics.nori.lan` (operator); cross-host reverse-proxied via station Caddy |
| Beszel agent | `services.beszel.agent` | both | Tailnet; hub pulls over tailnet |
| Gatus | `services.gatus` | both | `status.nori.lan` (public); mutual probes — Pi watches station, station watches Pi |
| ntfy server | `services.ntfy-sh` | pi | `alert.nori.lan` (operator); cross-host reverse-proxied |
| ntfy `notify@` template | systemd unit | both | Each host's units POST directly, hostname-aware via `config.networking.hostName` |
| **Tailnet** | | | |
| Tailscale | `services.tailscale` | both | N/A |
| **Backup** | | | |
| restic jobs | `services.restic.backups.<n>` | workstation | N/A (outbound to Pi + Hetzner) |
| btrbk | `services.btrbk.instances.<n>` | workstation | N/A (local snapshot) |
| postgresqlBackup | `services.postgresqlBackup` | workstation (non-Immich PG) | N/A |
| **Desktop** | | | |
| Thunar | `programs.thunar` | workstation | Local desktop only |

Cross-host services use the split-module pattern (TOPOLOGY.md § cross-host services).

### About Immich's Postgres

`services.immich.database.enable = true` provisions a Postgres instance owned by Immich, separate from `services.postgresql`. NixOS 25.11+ uses VectorChord (replacing pgvecto-rs) and Postgres 17 by default. Immich's own database management writes periodic dumps to `/var/lib/immich/backups/`. Backup Pattern B picks up those dumps rather than running an external `pg_dump`.

## Backup-correctness patterns

Three flavors depending on service type. All use `services.restic.backups.<n>`; the differences are in *what they back up* and *what runs before the backup*.

| Pattern | When | Implementation | Example |
|---|---|---|---|
| **A: Filesystem-only** | data isn't a database | restic targets paths directly | Jellyfin lib, Samba shares, `/home`, `/srv/share` |
| **B: Built-in dump** | service writes its own SQL dumps | restic picks up the dump dir | Immich |
| **C1: External dump (Postgres)** | system Postgres without internal dump | `services.postgresqlBackup` + restic picks up the dump dir | shared Postgres |
| **C2: External dump (SQLite)** | service writes SQLite without internal dump | `backupPrepareCommand = sqlite3 .backup` on the restic job | Open WebUI |

### Pattern A — filesystem-only

```nix
services.restic.backups.home = {
  paths = [ "/home" "/srv/share" ];
  repository = "sftp:pi:/mnt/backup/home";
  passwordFile = config.sops.secrets.restic-password.path;
  timerConfig.OnCalendar = "daily";
  pruneOpts = [ "--keep-daily 14" "--keep-weekly 4" "--keep-monthly 12" ];
};
```

### Pattern B — built-in dump (Immich)

The directory is included in `/var/lib`; restic of `/var/lib/immich` plus the upload directories is sufficient *if and only if* Immich's internal backup is enabled and the timer beat the restic timer.

```nix
services.restic.backups.immich = {
  paths = [
    "/var/lib/immich/backups"     # SQL dumps (consistent point-in-time)
    "/var/lib/immich/upload"       # User uploads
    "/var/lib/immich/library"      # Imported library
    "/var/lib/immich/profile"      # User profiles
  ];
  repository = "sftp:pi:/mnt/backup/immich";
  passwordFile = config.sops.secrets.restic-password.path;
  timerConfig.OnCalendar = "*-*-* 04:00:00";  # After Immich's nightly dump
  pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
};
```

### Pattern C1 — `services.postgresqlBackup`

```nix
services.postgresqlBackup = {
  enable = true;
  databases = [ "openwebui" ];
  startAt = "*-*-* 03:30:00";
  pgdumpOptions = "--no-owner";
  location = "/var/backup/postgresql";
};
# Then restic backs up /var/backup/postgresql alongside other paths.
```

### Pattern C2 — `backupPrepareCommand` (SQLite)

```nix
services.restic.backups.openwebui = {
  paths = [
    "/var/lib/open-webui"
    "/var/backup/open-webui"  # where the dump lands
  ];
  repository = "sftp:pi:/mnt/backup/openwebui";
  passwordFile = config.sops.secrets.restic-password.path;
  backupPrepareCommand = ''
    mkdir -p /var/backup/open-webui
    ${pkgs.sqlite}/bin/sqlite3 /var/lib/open-webui/webui.db \
      ".backup '/var/backup/open-webui/webui.db'"
  '';
  timerConfig.OnCalendar = "daily";
};
```

`backupPrepareCommand` runs as `ExecStartPre` on the generated `restic-backups-<name>.service`. SQLite's `.backup` API produces a consistent snapshot even on a live database; raw `cp` does not.

### Pattern selection cheat sheet

| Service | Pattern | Rationale |
|---|---|---|
| Jellyfin | A | Library DB is SQLite but rebuilds from media; non-critical |
| Immich | B | Built-in dump mechanism |
| Open WebUI | C2 | SQLite, no internal dump |
| Ollama | A | Models are re-downloadable |
| Tailscale | A | State files |
| `/home`, `/srv/share` | A | No databases |

New services pick a pattern at onboarding (`/add-service`).

## Observability and alerting

| Plane | Tool | Why |
|---|---|---|
| Metrics | **Beszel** (hub on Pi, agents on both hosts) | When workstation hangs, the hub on Pi keeps recording its metrics up to the last poll — forensics use case |
| Synthetic checks | **Gatus** (mutual probes — Pi watches station, station watches Pi) | Pure declarative — endpoints, conditions, alert routing all live in the Nix attrset that renders to gatus's YAML. Replaced an earlier Uptime Kuma plan once code-as-config friction surfaced |
| Alert delivery | **ntfy** (self-hosted server on Pi; per-host `notify@` template POSTs directly) | High-priority topic for urgent (sound, bypass DND); normal priority for warnings. Pi hosts the server so an unreachable workstation still surfaces alerts |

### Monitored conditions

| Condition | Source | Severity |
|---|---|---|
| Filesystem >80% full | Beszel | Warn |
| Filesystem >90% full | Beszel | Urgent |
| SMART status changes | systemd timer | Urgent |
| Service down (HTTP / TCP probe) | Gatus | Urgent |
| Tailscale connectivity loss | systemd timer | Urgent |
| restic backup job failure | restic systemd unit (`OnFailure → notify@`) | Urgent |
| btrbk snapshot job failure | btrbk systemd unit | Warn |
| Sustained high CPU/memory | Beszel | Warn |

### Alert delivery

| Type | Channel | Trigger |
|---|---|---|
| Real-time, low priority | ntfy default topic | Warnings |
| Real-time, high priority | ntfy urgent topic | Service down, drive failing, backup failed |
| Routine summary | Email digest (deferred) | All metrics summarized; SMTP via Gmail app password when set up |

Email digest deferred. When it lands: Gmail SMTP with app password (sufficient for machine-generated reports; Proton Bridge's complexity isn't warranted for non-private content).

## Self-deployed apps

`secrets/apps.yaml` (separate sops file from `secrets/secrets.yaml`) holds tokens for the operator's personal apps deployed on the homelab. Per-secret `sopsFile = ../../secrets/apps.yaml` override on the consuming module.

Naming convention: agnostic (`tmdb-token`, not `filmder-tmdb-token`) when multiple projects could plausibly share the same key.

Live worked example: `modules/server/filmder.nix` — sops decrypt → systemd build oneshot (manual trigger via `just deploy-app filmder`, sentinel-skip on idempotent rebuilds, `bun install + bun run build`) → atomic publish to `/var/lib/<n>/dist` → darkhttpd-on-port → `nori.lanRoutes` for `<n>.nori.lan`. Internet-public exposure prototyped via Tailscale Funnel and reverted; reference preserved in `memory/reference/tailscale_funnel_implementation.md`.
