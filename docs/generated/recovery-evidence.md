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
| `immich` | `workstation` | `application-export` | `media-irreplaceable` | `onetouch` | `/mnt/media/archive`<br>`/mnt/media/home-videos`<br>`/mnt/media/library`<br>`/mnt/media/photos`<br>`/mnt/media/projects` | — | `immich-export` |
| `jellyfin` | `workstation` | `filesystem` | `jellyfin` | `onetouch` | `/var/lib/jellyfin` | — | `jellyfin-metadata` |
| `miniflux` | `adelie` | `postgresql-logical` | `miniflux` | `onetouch` | `/var/backup/postgresql/miniflux.sql.gz` | — | `miniflux-database` |
| `navidrome` | `workstation` | `sqlite-logical` | `navidrome` | `onetouch` | `/var/lib/private/navidrome`<br>`/var/backup/navidrome` | — | — |
| `pihole` | `pi` | `filesystem` | `pihole` | `onetouch` | `/var/lib/containers/storage/volumes/pihole-data/_data`<br>`/opt/pihole/dnsmasq.d/05-homelab-local-records.conf` | — | `pihole-service` |
| `stremio` | `adelie` | `filesystem` | `stremio` | `onetouch` | `/var/lib/stremio` | `/var/lib/stremio/stremio-cache` | `stremio-identity` |
| `vaultwarden` | `adelie` | `sqlite-logical` | `vaultwarden` | `onetouch` | `/var/lib/vaultwarden`<br>`/var/backup/vaultwarden` | — | `vaultwarden-database` |

## Recorded recovery evidence

Gates are historical report checkpoints, not live status or current
configuration conformance.

| Evidence | Scope | Workload | Host | Model | Backup job | Current targets | Current include paths | Current exclude paths | Observed gates | Report |
|---|---|---|---|---|---|---|---|---|---|---|
| `immich-export` | `service` | `immich` | `workstation` | `application-export` | `media-irreplaceable` | `onetouch` | `/mnt/media/archive`<br>`/mnt/media/home-videos`<br>`/mnt/media/library`<br>`/mnt/media/photos`<br>`/mnt/media/projects` | — | `restore`<br>`hash-equality`<br>`import`<br>`row-equality` | [report](../archive/reports/2026-09-21-immich-export-recovery-drill.md) |
| `jellyfin-metadata` | `service` | `jellyfin` | `workstation` | `filesystem` | `jellyfin` | `onetouch` | `/var/lib/jellyfin` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-jellyfin-metadata-recovery-drill.md) |
| `miniflux-database` | `service` | `miniflux` | `adelie` | `postgresql-logical` | `miniflux` | `onetouch` | `/var/backup/postgresql/miniflux.sql.gz` | — | `restore`<br>`import`<br>`migration`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-miniflux-postgresql-recovery-drill.md) |
| `pi-host` | `host` | — | `pi` | `filesystem` | `pihole` | `onetouch` | `/var/lib/containers/storage/volumes/pihole-data/_data`<br>`/opt/pihole/dnsmasq.d/05-homelab-local-records.conf` | — | `convergence`<br>`idempotence`<br>`restore`<br>`reboot`<br>`endpoint` | [report](../archive/reports/2026-09-21-pi-host-reconstruction-drill.md) |
| `pihole-service` | `service` | `pihole` | `pi` | `filesystem` | `pihole` | `onetouch` | `/var/lib/containers/storage/volumes/pihole-data/_data`<br>`/opt/pihole/dnsmasq.d/05-homelab-local-records.conf` | — | `restore`<br>`integrity`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-pihole-recovery-drill.md) |
| `stremio-identity` | `service` | `stremio` | `adelie` | `filesystem` | `stremio` | `onetouch` | `/var/lib/stremio` | `/var/lib/stremio/stremio-cache` | `restore`<br>`startup`<br>`endpoint` | [report](../archive/reports/2026-09-21-stremio-files-recovery-drill.md) |
| `user-data` | `data` | — | `workstation` | `filesystem` | `user-data` | `onetouch` | `/home`<br>`/srv/nori`<br>`/srv/share` | `/home/nori/.codex/.tmp`<br>`/home/nori/.codex/cache`<br>`/home/nori/.codex/ipc`<br>`/home/nori/.codex/logs_2.sqlite`<br>`/home/nori/.codex/logs_2.sqlite-shm`<br>`/home/nori/.codex/logs_2.sqlite-wal`<br>`/home/nori/.codex/mcp-oauth-locks`<br>`/home/nori/.codex/models_cache.json`<br>`/home/nori/.codex/shell_snapshots`<br>`/home/nori/.codex/vendor_imports`<br>`/home/nori/.claude/backups`<br>`/home/nori/.claude/cache`<br>`/home/nori/.claude/daemon`<br>`/home/nori/.claude/paste-cache`<br>`/home/nori/.claude/plugins/cache`<br>`/home/nori/.claude/remote`<br>`/home/nori/.claude/shell-snapshots` | `restore`<br>`hash-equality`<br>`metadata` | [report](../archive/reports/2026-09-21-user-data-recovery-drill.md) |
| `vaultwarden-database` | `service` | `vaultwarden` | `adelie` | `sqlite-logical` | `vaultwarden` | `onetouch` | `/var/lib/vaultwarden`<br>`/var/backup/vaultwarden` | — | `restore`<br>`import`<br>`migration`<br>`endpoint` | [report](../archive/reports/2026-09-21-vaultwarden-sqlite-recovery-drill.md) |
