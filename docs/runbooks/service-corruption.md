# Service state corruption

**RTO**: <1 hour. Stop service → restore subvolume snapshot → restart → verify.

## Symptom

A service's database / state got corrupted — Open WebUI won't start with "database is malformed", Jellyfin library shows wrong metadata, Authelia login broken after a config edit, etc. Service binary is fine; its state is what's wrong.

## Three flavors of restore

Pattern matches DESIGN.md L210-289. The right flavor depends on how the service stores state.

### Pattern A — filesystem-only (Jellyfin, Tailscale, Cloudflared, plain Pattern-A services)

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
curl -k https://media.nori.lan/health
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

### Pattern C — external dump pre-restic (Open WebUI / SQLite)

The `backupPrepareCommand` writes a logical dump to `/var/backup/open-webui/webui.db` before restic backs it up. Restore from that dump (or, if it's also corrupt, from a restic snapshot of it):

```bash
sudo systemctl stop open-webui.service
sudo mv /var/lib/open-webui/webui.db /var/lib/open-webui/webui.db.broken
# Restore the most recent good dump
sudo cp /var/backup/open-webui/webui.db /var/lib/open-webui/webui.db
sudo chown --reference=/var/lib/open-webui /var/lib/open-webui/webui.db
sudo systemctl start open-webui.service
```

If `/var/backup/open-webui/webui.db` is also bad, pull from restic:

```bash
sudo restic -r /mnt/backup/open-webui \
  --password-file /run/secrets/restic-password \
  restore latest --target /tmp/restore \
  --include /var/backup/open-webui/webui.db
sudo cp /tmp/restore/var/backup/open-webui/webui.db /var/lib/open-webui/webui.db
sudo chown --reference=/var/lib/open-webui /var/lib/open-webui/webui.db
```

## Verify

After every restore: hit a real endpoint, not just `systemctl status`. Status says "active" before the service has finished its startup checks.

| Service | Verification |
|---|---|
| Jellyfin | log in, browse a library |
| Open WebUI | log in via OIDC, see chat history |
| Authelia | OIDC redirect from a downstream service succeeds |
| Beszel | open `https://metrics.nori.lan`, see live agent data |
| Immich | open the timeline, see a recent photo's metadata |

## When to escalate

If the restore from snapshot also has the corruption, the corruption has been there long enough to be in every snapshot. Try restic — daily snapshots persist 7d / 4w / 12m, so older states are reachable.

If restic also has it: the corruption is older than your retention. Service data is effectively lost; configure the service from scratch and recover any rebuildable content (Jellyfin re-scans media; Immich re-imports from upload dir; Open WebUI re-issues OIDC dance).
