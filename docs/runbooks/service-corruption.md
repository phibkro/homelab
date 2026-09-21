# Service state corruption

**RTO**: <1 hour. Stop service → restore subvolume snapshot → restart → verify.

## Symptom

A service's state is corrupt. For example, Vaultwarden can report a malformed
database, Jellyfin can show incorrect metadata, or Authelia can reject login
after a state change. The service binary is healthy, but its state is not.

## Four recovery patterns

Select the matching pattern from the
[service reference](../reference/services.md#backup-correctness-patterns).

### Pattern A — filesystem-only (Jellyfin, Tailscale, plain Pattern-A services)

```bash
# 1. Stop service
sudo systemctl stop jellyfin.service

# 2. Move the corrupt state aside (don't delete; it's evidence)
sudo mv /var/lib/jellyfin /var/lib/jellyfin.broken-$(date +%s)

# 3. Restore from latest btrbk snapshot (lives on @var-lib)
sudo cp -aR /.snapshots/var/lib.<timestamp>/jellyfin /var/lib/jellyfin

# 4. Restart
sudo systemctl start jellyfin.service

# 5. Verify (service-specific)
sudo systemctl status jellyfin.service
curl https://media.home.phibkro.org/health
```

### Pattern B — service with built-in dump (Immich)

Immich writes its own SQL dumps to `/var/lib/immich/backups/`. Restore by replaying the most recent dump on a fresh DB:

```bash
sudo systemctl stop immich-server.service immich-machine-learning.service
# Drop + recreate the database (Immich's docs walk through this)
sudo -u postgres psql -c "DROP DATABASE immich;"
sudo -u postgres psql -c "CREATE DATABASE immich;"
# Replay the latest dump
sudo -u postgres psql immich < /var/lib/immich/backups/dump-<latest>.sql
# Restart
sudo systemctl start immich-server.service immich-machine-learning.service
```

### Pattern C1 — PostgreSQL logical dump (Miniflux)

`services.postgresqlBackup` writes
`/var/backup/postgresql/miniflux.sql.gz`. The Miniflux Restic unit requires a
fresh dump before it can run.

Restore the selected snapshot to a disposable directory. Import the dump into
a new PostgreSQL cluster with `ON_ERROR_STOP` enabled. Start Miniflux against
that cluster and require `/healthcheck` to return HTTP 200 before a production
cutover. The verified isolated sequence is recorded in
`../archive/reports/2026-09-21-miniflux-postgresql-recovery-drill.md`.

### Pattern C2 — prepared database before Restic (Vaultwarden / SQLite)

`nori.backups.vaultwarden.prepareCommand` uses `VACUUM INTO` before each
Restic run. This creates `/var/backup/vaultwarden/db.sqlite3`.

Restore the selected Restic snapshot to a disposable directory first. Adelie
uses restricted SFTP, not a local `/mnt/backup` repository. Reuse the
repository, credential, and pinned transport from the deployed
`restic-backups-vaultwarden-onetouch.service`. Do not replace its host check.

Validate the restored logical database before production replacement:

```bash
sudo nix shell nixpkgs#sqlite.bin -c sqlite3 \
  <restore>/var/backup/vaultwarden/db.sqlite3 \
  'PRAGMA integrity_check;'
```

Continue only when the command returns `ok`:

```bash
sudo systemctl stop vaultwarden.service
sudo mv /var/lib/vaultwarden/db.sqlite3 \
  /var/lib/vaultwarden/db.sqlite3.broken-$(date +%s)
sudo install -o vaultwarden -g vaultwarden -m 0600 \
  <restore>/var/backup/vaultwarden/db.sqlite3 \
  /var/lib/vaultwarden/db.sqlite3
sudo systemctl start vaultwarden.service
curl --fail --silent --show-error http://127.0.0.1:8222/alive
```

## Verify

After every restore, use a real endpoint. `systemctl status` can report
`active` before startup checks finish.

| Service | Verification |
|---|---|
| Jellyfin | Log in and browse a library |
| Vaultwarden | `/alive` returns HTTP 200; log in and open one vault item |
| Authelia | Complete an OIDC redirect from a downstream service |
| Beszel | Open `https://metrics.home.phibkro.org` and view current agent data |
| Immich | Open the timeline and view recent photo metadata |

## When to escalate

If the restore from snapshot also has the corruption, the corruption has been there long enough to be in every snapshot. Try restic — daily snapshots persist 7d / 4w / 12m, so older states are reachable.

If Restic also contains the corruption, the retained history is insufficient.
Reconfigure the service and recover rebuildable data or an independent export.
