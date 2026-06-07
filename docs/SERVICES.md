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
| Beszel agent | `services.beszel.agent` | workstation + pi | Hub pulls over tailnet |
| Gatus | `services.gatus` | workstation + pi | `status.nori.lan` (public); mutual probes — Pi watches station, station watches Pi |
| **VictoriaMetrics** | `services.victoriametrics` | pi | TSDB scraping gatus + node-exporter + process-exporter; Grafana datasource. Two-week retention |
| **VictoriaLogs** | `services.victorialogs` | pi | `logs.nori.lan` (operator); journald aggregator; 14d retention |
| **Vector** | `modules/common/vector.nix` | every host | Ships journald → VictoriaLogs over tailnet; structured parsing |
| **Grafana** | `services.grafana` | workstation | `ops.nori.lan` (operator); VM + VL datasources |
| **node-exporter** | `services.prometheus.exporters.node` | workstation + pavilion + aurora | Port 9100 (tailnet); scraped from pi VM |
| **process-exporter** | `services.prometheus.exporters.process` | workstation + pavilion + aurora | Port 9256 (tailnet); CAP_SYS_PTRACE granted; per-`comm` RSS |
| **ntfy server** (pi-local) | `services.ntfy-sh` | pi | `alert.nori.lan` (operator); reserved for future internal-only alerts. **Production alerts go to ntfy.sh public** (off-pi, surviving pi outage) |
| **ntfy `notify@` template** | systemd unit | every host | POSTs to ntfy.sh public; hostname-aware via `config.networking.hostName` |
| **heartbeat** | `modules/services/heartbeat.nix` | pi | Dead-man-switch; ping healthchecks.io every 60s. SPOF mitigation |
| **Agents** | | | |
| Hermes Agent | `modules/services/hermes.nix` (route) + `home/hermes/` (CLI) | workstation (today) | `hermes.nori.lan` (operator); dashboard 9119 |
| **ML offload** | | | |
| immich-machine-learning | `modules/services/immich-ml.nix` (aurora) | **aurora** | RPC only (3003); `IMMICH_MACHINE_LEARNING_URL` on workstation |
| **Tailnet** | | | |
| Tailscale | `services.tailscale` | every host | N/A |
| **Backup** | | | |
| restic jobs | `services.restic.backups.<n>` | workstation | Dual-target → `/mnt/backup/` (OneTouch) + `/mnt/backup-local/` (Ironwolf); Hetzner deferred |
| btrbk | `services.btrbk.instances.<n>` | workstation | Local snapshot |
| postgresqlBackup | `services.postgresqlBackup` | workstation (non-Immich PG) | N/A |
| restore-drill (services tier) | `modules/services/backup/verify.nix` | workstation | Monthly; 17 service repos restored to `/var/restore-test/` |
| restore-drill (user-data tier) | same | workstation | Quarterly; user-data tier (~99 GiB) |
| **Desktop** | | | |
| Thunar | `programs.thunar` + tumbler + xarchiver | workstation | Local desktop only |

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
nori.backups.user-data = {
  include = [ "/home" "/srv/share" "/srv/nori" ];
  tier = "user";  # drives default retention curve
};
# Generates `restic-backups-user-data-onetouch.service` (→ /mnt/backup/user-data)
# AND `restic-backups-user-data-ironwolf.service` (→ /mnt/backup-local/user-data)
```

Don't write `services.restic.backups.<n>` directly — `nori.backups.<n>` is the homelab abstraction; generators expand it into both restic units + the `every-service-has-backup-intent` flake check coverage.

### Pattern B — built-in dump (Immich)

The directory is included in `/var/lib`; restic of `/var/lib/immich` plus the upload directories is sufficient *if and only if* Immich's internal backup is enabled and the timer beat the restic timer.

```nix
nori.backups.immich = {
  include = [
    "/var/lib/immich/backups"   # SQL dumps (consistent point-in-time)
    "/var/lib/immich/upload"    # user uploads
    "/var/lib/immich/library"   # imported library
    "/var/lib/immich/profile"   # user profiles
  ];
  tier = "irreplaceable";
  timer = "*-*-* 04:00:00";  # after Immich's nightly dump beats restic's
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

### Pattern C2 — `prepareCommand` with VACUUM INTO + flock (SQLite)

⚠ Two traps caught in production:

| Trap | Fix | Memory entry |
|---|---|---|
| sqlite3 CLI's `.backup` ignores `busy_timeout` (hard-coded ~2.5s retry) → "database is locked" on the first concurrent writer | Use `VACUUM INTO` + `PRAGMA busy_timeout` (regular SQL, honours the pragma) | [[sqlite-backup-vacuum-into]] |
| `-onetouch` + `-ironwolf` restic units fire same minute → both run `prepareCommand` → race on `.tmp` → "table … already exists" | Wrap rm/sqlite/mv in `flock` (file-descriptor form, subshell-scoped) | [[pattern-c2-sqlite-race-flock]] |

Canonical impl — `modules/services/navidrome.nix`:

```nix
nori.backups.navidrome = {
  include = [ "/var/lib/navidrome" "/var/backup/navidrome" ];
  prepareCommand = ''
    if [ -f /var/lib/navidrome/navidrome.db ]; then
      mkdir -p /var/backup/navidrome
      (
        ${pkgs.util-linux}/bin/flock -x 9
        rm -f /var/backup/navidrome/navidrome.db.tmp
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/navidrome/navidrome.db \
          "PRAGMA busy_timeout = 30000;" \
          "VACUUM INTO '/var/backup/navidrome/navidrome.db.tmp';"
        mv /var/backup/navidrome/navidrome.db.tmp /var/backup/navidrome/navidrome.db
      ) 9>/var/backup/navidrome/.prep.lock
    fi
  '';
  timer = "*-*-* 04:45:00";
};
```

`prepareCommand` runs as `ExecStartPre` on BOTH `restic-backups-<n>-onetouch.service` AND `-ironwolf.service`. flock serialises them; second caller does a redundant (cheap) dump on already-fresh state. `VACUUM INTO` requires destination absent — that's why `rm -f` precedes it.

Runtime check: `just test-backups` asserts per-target snapshot ≤25h.

### Pattern selection cheat sheet

| Service | Pattern | Rationale |
|---|---|---|
| Jellyfin | A | Library DB is SQLite but rebuilds from media; non-critical |
| Immich | B | Built-in dump mechanism |
| Open WebUI | C2 | SQLite, no internal dump |
| Vaultwarden | C2 | SQLite (diesel migrations); race fix applied |
| Navidrome | C2 | SQLite (goose migrations); canonical impl reference |
| Ollama | A | Models are re-downloadable |
| Tailscale | A | State files |
| `/home`, `/srv/share`, `/srv/nori` | A (via `nori.backups.user-data`) | No databases |

New services pick a pattern at onboarding (`/add-service`). Pattern C2 services MUST use the flock-wrapped canonical impl — failure mode = silent half-failure (ironwolf succeeds, onetouch fails to race, ntfy fires).

## Observability and alerting

```mermaid
flowchart TB
  subgraph workhorse[workhorse hosts]
    WS[workstation]
    AU[aurora]
    PV[pavilion]
  end
  subgraph appliance[pi - appliance tier]
    VM[VictoriaMetrics<br/>:8428]
    VL[VictoriaLogs<br/>:9428]
    GA[Gatus]
    BES[Beszel hub]
  end
  WS -- node-exporter:9100<br/>process-exporter:9256 --> VM
  AU -- same --> VM
  PV -- same --> VM
  WS -- journald via vector --> VL
  AU -- same --> VL
  PV -- same --> VL
  GA -- mutual probe --> WS
  WS -. Grafana queries .-> VM
  WS -. Grafana queries .-> VL
  Pi[heartbeat] --> HC[healthchecks.io]
  GA -- alert --> Public[ntfy.sh public]
  notify[notify@ template<br/>per-host] --> Public
```

| Plane | Tool | Where | Why |
|---|---|---|---|
| **Metrics (system)** | Beszel hub + agent | pi (hub); workhorse hosts (agent) | Forensics: when workstation hangs, Pi's hub keeps recording up to last poll |
| **Metrics (TSDB)** | VictoriaMetrics | pi | Scrapes gatus + node-exporter + process-exporter; 14d retention |
| **Logs (TSDB)** | VictoriaLogs | pi | Aggregates journald via vector shipper; 14d retention. `just query-logs <LogsQL>` |
| **Per-process RSS** | process-exporter | workstation + pavilion + aurora | Leak hunter; pi VM scrapes. See [[workstation-leak-hunting]] |
| **Synthetic checks** | Gatus | workstation + pi | Mutual probes; declarative attrset → YAML. Replaced Uptime Kuma |
| **Dashboards** | Grafana | workstation | VM + VL as datasources; per-host system + gatus dashboards |
| **Alert delivery** | ntfy.sh **public** | every host | `notify@<unit>.service` POSTs directly; channel-secret in sops. Pi-local ntfy server reserved for future internal alerts |
| **Dead-man-switch** | healthchecks.io | pi → external | 60s ping; alerts off-host if pi dies. SPOF mitigation |
| **Runtime test** | `just test-observability` | operator-triggered | Asserts VM targets up + per-host series + heartbeat <90s + zero failing probes. See `docs/RUNTIME_TESTS.md` |

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

Live worked example: `modules/services/filmder.nix` — sops decrypt → systemd build oneshot (manual trigger via `just deploy-app filmder`, sentinel-skip on idempotent rebuilds, `bun install + bun run build`) → atomic publish to `/var/lib/<n>/dist` → darkhttpd-on-port → `nori.lanRoutes` for `<n>.nori.lan`. Internet-public exposure prototyped via Tailscale Funnel and reverted; reference preserved in `memory/reference/tailscale_funnel_implementation.md`.
