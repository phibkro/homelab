---
generated: true
source: lib/flake-parts/packages/docs-recovery-evidence.nix
regenerate: nix build .#docs-recovery-evidence
---

# Recovery contracts and evidence

This view joins three distinct sources without treating them as the
same claim:

- workload manifests own service identity, placement, and recovery model;
- evaluated backup jobs own targets, included paths, and exclusions;
- `inventory/recovery-evidence.nix` indexes recorded dated reports.

A configured backup is not recovery evidence. An evidence link joins
the same subject; it does not claim that the report exercised the
current declaration. The report's source revision controls that
boundary. Read it for snapshot identity, results, limits, and cleanup.

The complete evaluated job inventory remains in
[`backups.md`](backups.md). A job omitted here has no workload recovery
contract; omission is not a live coverage verdict.

## Declared workload recovery contracts

| Workload | Host | Model | Backup job | Targets | Include paths | Exclude paths | Related evidence |
|---|---|---|---|---|---|---|---|
| `authelia` | `pi` | `filesystem` | `authelia` | `onetouch` | `/etc/authelia/configuration.yml`<br>`/etc/authelia/users_database.yml`<br>`/var/lib/authelia` | — | `authelia-service` |
| `beszel-hub` | `pi` | `filesystem` | `beszel` | `onetouch` | `/var/lib/beszel` | — | `beszel-service` |
| `caddy` | `pi` | `filesystem` | `caddy` | `onetouch` | `/opt/caddy/data`<br>`/opt/caddy/config` | — | `caddy-service` |
| `immich` | `workstation` | `application-export` | `media-irreplaceable` | `onetouch` | `/mnt/media/archive`<br>`/mnt/media/home-videos`<br>`/mnt/media/library`<br>`/mnt/media/photos`<br>`/mnt/media/projects` | — | `immich-export` |
| `jellyfin` | `workstation` | `filesystem` | `jellyfin` | `onetouch` | `/var/lib/jellyfin` | — | `jellyfin-metadata` |
| `miniflux` | `adelie` | `postgresql-logical` | `miniflux` | `onetouch` | `/var/backup/postgresql/miniflux.sql.gz` | — | `miniflux-database` |
| `navidrome` | `workstation` | `sqlite-logical` | `navidrome` | `onetouch` | `/var/lib/private/navidrome`<br>`/var/backup/navidrome` | — | — |
| `ntfy-server` | `pi` | `filesystem` | `ntfy` | `onetouch` | `/var/cache/ntfy`<br>`/var/lib/ntfy` | — | `ntfy-service` |
| `pihole` | `pi` | `filesystem` | `pihole` | `onetouch` | `/var/lib/containers/storage/volumes/pihole-data/_data`<br>`/opt/pihole/dnsmasq.d/05-homelab-local-records.conf` | — | `pihole-service` |
| `stremio` | `adelie` | `filesystem` | `stremio` | `onetouch` | `/var/lib/stremio` | `/var/lib/stremio/stremio-cache` | `stremio-identity` |
| `vaultwarden` | `adelie` | `sqlite-logical` | `vaultwarden` | `onetouch` | `/var/lib/vaultwarden`<br>`/var/backup/vaultwarden` | — | `vaultwarden-database` |
| `victorialogs-server` | `pi` | `filesystem` | `victorialogs` | `onetouch` | `/var/lib/victorialogs` | — | `victorialogs-service` |
| `victoriametrics` | `pi` | `filesystem` | `victoriametrics` | `onetouch` | `/var/lib/victoriametrics`<br>`/etc/victoriametrics` | — | `victoriametrics-service` |

## Recorded recovery evidence

Gates are historical report checkpoints, not live status or current
configuration conformance. `Observed` and `max age` are the
authoritative freshness inputs used by the runtime evidence-age
monitor.

| Evidence | Scope | Workload | Host | Model | Backup job | Observed | Max age (days) | Current targets | Current include paths | Current exclude paths | Observed gates | Report |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `authelia-service` | `service` | `authelia` | `pi` | `filesystem` | `authelia` | `2026-09-21` | `120` | `onetouch` | `/etc/authelia/configuration.yml`<br>`/etc/authelia/users_database.yml`<br>`/var/lib/authelia` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint`<br>`oidc-discovery` | [report](../archive/reports/2026-09-21-authelia-recovery-drill.md) |
| `beszel-service` | `service` | `beszel-hub` | `pi` | `filesystem` | `beszel` | `2026-09-21` | `120` | `onetouch` | `/var/lib/beszel` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint`<br>`data-block-integrity` | [report](../archive/reports/2026-09-21-pi-service-recovery-closure.md) |
| `caddy-service` | `service` | `caddy` | `pi` | `filesystem` | `caddy` | `2026-09-21` | `120` | `onetouch` | `/opt/caddy/data`<br>`/opt/caddy/config` | — | `restore`<br>`validation`<br>`endpoint`<br>`data-block-integrity` | [report](../archive/reports/2026-09-21-pi-service-recovery-closure.md) |
| `immich-export` | `service` | `immich` | `workstation` | `application-export` | `media-irreplaceable` | `2026-09-21` | `120` | `onetouch` | `/mnt/media/archive`<br>`/mnt/media/home-videos`<br>`/mnt/media/library`<br>`/mnt/media/photos`<br>`/mnt/media/projects` | — | `restore`<br>`hash-equality`<br>`import`<br>`row-equality` | [report](../archive/reports/2026-09-21-immich-export-recovery-drill.md) |
| `jellyfin-metadata` | `service` | `jellyfin` | `workstation` | `filesystem` | `jellyfin` | `2026-09-21` | `120` | `onetouch` | `/var/lib/jellyfin` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-jellyfin-metadata-recovery-drill.md) |
| `miniflux-database` | `service` | `miniflux` | `adelie` | `postgresql-logical` | `miniflux` | `2026-09-21` | `120` | `onetouch` | `/var/backup/postgresql/miniflux.sql.gz` | — | `restore`<br>`import`<br>`migration`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-miniflux-postgresql-recovery-drill.md) |
| `ntfy-service` | `service` | `ntfy-server` | `pi` | `filesystem` | `ntfy` | `2026-09-21` | `120` | `onetouch` | `/var/cache/ntfy`<br>`/var/lib/ntfy` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-ntfy-recovery-drill.md) |
| `pi-host` | `host` | — | `pi` | `filesystem` | `pihole` | `2026-09-21` | `120` | `onetouch` | `/var/lib/containers/storage/volumes/pihole-data/_data`<br>`/opt/pihole/dnsmasq.d/05-homelab-local-records.conf` | — | `convergence`<br>`idempotence`<br>`restore`<br>`reboot`<br>`endpoint` | [report](../archive/reports/2026-09-21-pi-host-reconstruction-drill.md) |
| `pihole-service` | `service` | `pihole` | `pi` | `filesystem` | `pihole` | `2026-09-21` | `120` | `onetouch` | `/var/lib/containers/storage/volumes/pihole-data/_data`<br>`/opt/pihole/dnsmasq.d/05-homelab-local-records.conf` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-pihole-recovery-drill.md) |
| `stremio-identity` | `service` | `stremio` | `adelie` | `filesystem` | `stremio` | `2026-09-21` | `120` | `onetouch` | `/var/lib/stremio` | `/var/lib/stremio/stremio-cache` | `restore`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-stremio-files-recovery-drill.md) |
| `user-data` | `data` | — | `workstation` | `filesystem` | `user-data` | `2026-09-21` | `120` | `onetouch` | `/home`<br>`/srv/nori`<br>`/srv/share` | `/home/nori/.codex/.tmp`<br>`/home/nori/.codex/cache`<br>`/home/nori/.codex/ipc`<br>`/home/nori/.codex/logs_2.sqlite`<br>`/home/nori/.codex/logs_2.sqlite-shm`<br>`/home/nori/.codex/logs_2.sqlite-wal`<br>`/home/nori/.codex/mcp-oauth-locks`<br>`/home/nori/.codex/models_cache.json`<br>`/home/nori/.codex/shell_snapshots`<br>`/home/nori/.codex/vendor_imports`<br>`/home/nori/.claude/backups`<br>`/home/nori/.claude/cache`<br>`/home/nori/.claude/daemon`<br>`/home/nori/.claude/paste-cache`<br>`/home/nori/.claude/plugins/cache`<br>`/home/nori/.claude/remote`<br>`/home/nori/.claude/shell-snapshots` | `restore`<br>`hash-equality`<br>`metadata` | [report](../archive/reports/2026-09-21-user-data-recovery-drill.md) |
| `vaultwarden-database` | `service` | `vaultwarden` | `adelie` | `sqlite-logical` | `vaultwarden` | `2026-09-21` | `120` | `onetouch` | `/var/lib/vaultwarden`<br>`/var/backup/vaultwarden` | — | `restore`<br>`import`<br>`migration`<br>`endpoint` | [report](../archive/reports/2026-09-21-vaultwarden-sqlite-recovery-drill.md) |
| `vector-pipeline` | `service` | — | `pi` | `filesystem` | `vector` | `2026-09-21` | `120` | `onetouch` | `/var/lib/vector`<br>`/etc/vector` | — | `restore`<br>`validation`<br>`startup`<br>`endpoint`<br>`data-block-integrity` | [report](../archive/reports/2026-09-21-pi-service-recovery-closure.md) |
| `victorialogs-service` | `service` | `victorialogs-server` | `pi` | `filesystem` | `victorialogs` | `2026-09-21` | `120` | `onetouch` | `/var/lib/victorialogs` | — | `restore`<br>`startup`<br>`endpoint`<br>`query`<br>`data-block-integrity` | [report](../archive/reports/2026-09-21-pi-service-recovery-closure.md) |
| `victoriametrics-service` | `service` | `victoriametrics` | `pi` | `filesystem` | `victoriametrics` | `2026-09-21` | `120` | `onetouch` | `/var/lib/victoriametrics`<br>`/etc/victoriametrics` | — | `restore`<br>`startup`<br>`endpoint`<br>`query`<br>`data-block-integrity` | [report](../archive/reports/2026-09-21-pi-service-recovery-closure.md) |
