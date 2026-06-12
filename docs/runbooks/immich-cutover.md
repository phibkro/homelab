---
summary: Step-by-step for the immich workstation→aurora cutover. The
  heaviest single-service migration in the aurora plan — postgres dump
  + restore (with the ownership-after-restore fix from
  [[postgres-ownership-after-dump-restore]]), photos data move covered
  by P10, then the Nix flip.
---

# immich cutover (P11 final)

This is the longest single-service step in
`docs/superpowers/plans/2026-06-11-aurora-migration.md` § P11. Pattern
matches the smaller migrations done this session (vaultwarden,
miniflux, …) but with three extra wrinkles:

1. **Bulk data lives under `/mnt/media/photos/_immich-managed/`** — so
   the P10 rsync IS the photos data move; no separate copy step.
2. **immich self-dumps the database to
   `/mnt/media/photos/_immich-managed/backups/immich-db-backup-*.sql.gz`**
   nightly at 02:00. The latest dump is the restore source — no need
   for `services.postgresqlBackup` to be involved.
3. **VectorChord + the vector / cube / pg_trgm / earthdistance /
   unaccent / uuid-ossp extensions all need to be present on the
   target before restore.** Aurora's `services.immich.database.enable
   = true` (already on per P8) provides all eight — verified identical
   to workstation's set:

       \dx → cube, earthdistance, pg_trgm, plpgsql, unaccent,
              uuid-ossp, vchord, vector

## Preconditions

- **P10 photos sync complete and verified.** The most recent
  `immich-db-backup-*.sql.gz` lands on aurora as a side effect of the
  photos rsync — `/mnt/family/photos/_immich-managed/backups/` is the
  source of truth post-rsync.
- **Aurora immich already running empty.** Standing up empty in P8
  (commit `e82bcb0`) means the postgres role, database, extensions,
  and redis socket are all in place — restore overwrites schema cleanly.
- **Workstation immich actively writing.** Cutover means a brief
  downtime; the latest 02:00 dump may be a few hours behind the live
  DB. Trigger a fresh dump first (step 1) so cutover loss is minutes,
  not hours.

## Steps

### 1. Fresh DB dump on workstation

Force immich to self-dump now rather than waiting for the next 02:00
window. The immich admin Settings → Database → Backup section has a
"Backup Now" button; clicking it writes a new
`immich-db-backup-<now>.sql.gz` into `_immich-managed/backups/`.
(Alternative: `sudo -u postgres pg_dump immich | gzip
 > /mnt/media/photos/_immich-managed/backups/immich-db-backup-cutover-$(date +%s).sql.gz`)

### 2. Stop immich on BOTH sides + final delta rsync

The `[[rsync-destination-service-ownership]]` trap bites here:
destination-side immich will claim `_immich-managed/` mid-transfer if
left running, breaking rsync with rc=23. Stop both sides; chown the
destination's `_immich-managed/` to a writable user for the delta
window; restore in step 4.

```sh
# source side
sudo systemctl stop immich-server immich-machine-learning
# destination side
ssh nori@aurora.saola-matrix.ts.net 'sudo systemctl stop immich-server immich-machine-learning'
ssh nori@aurora.saola-matrix.ts.net 'sudo chown -R nori:users /mnt/family/photos/_immich-managed'
# delta-sync any photos that landed between the P10 finish and now
sudo rsync -aHAX --info=stats2 --info=progress2 \
  --rsh="ssh -i /home/nori/.ssh/id_ed25519" \
  /mnt/media/photos/ nori@aurora.saola-matrix.ts.net:/mnt/family/photos/
```

### 3. Restore the DB on aurora (with the ownership fix baked in)

The `restore-pg-with-owner-fix` skill — invoke `/restore-pg-with-owner-fix`
or run its `restore.sh` directly — handles drop + recreate +
gunzip|psql restore + the ALTER OWNER sweep in one shot. The
ownership trap from [[postgres-ownership-after-dump-restore]] is
silent under load, and rediscovering it on immich (14+ tables,
vectorchord-managed extensions, minutes of restore) is exactly the
class of debugging the skill exists to avoid.

```sh
ssh nori@aurora.saola-matrix.ts.net
# pick the freshest dump
LATEST=$(sudo ls -t /mnt/family/photos/_immich-managed/backups/immich-db-backup-*.sql.gz | head -1)
sudo systemctl stop immich-server immich-machine-learning
sudo bash /srv/share/projects/homelab/.claude/skills/restore-pg-with-owner-fix/restore.sh \
  immich immich "$LATEST"
```

The script drops + recreates the immich DB owned by the immich role,
restores from the dump, then `ALTER ... OWNER TO immich`s every table
+ sequence + the public schema.

### 4. Sanity-check aurora restore

```sh
sudo -u postgres psql immich -c "SELECT count(*) FROM assets; SELECT count(*) FROM users;"
# both should match the workstation row counts (compare before stopping
# workstation immich at step 2):
#   ssh workstation sudo -u postgres psql immich \
#     -c 'SELECT count(*) FROM assets; SELECT count(*) FROM users;'
```

### 5. Nix flip (one commit)

Edit `modules/services/immich.nix`:
- `nori.lanRoutes.photos.runsOn = "aurora";`
- `host = "0.0.0.0";` (or pass `IMMICH_HOST = "0.0.0.0"`)

Aurora already has 2283 + 3003 open on tailnet (since P8), so no
firewall edit needed.

Edit `machines/workstation/default.nix`:
- `immich.enable = false;`

Edit `machines/aurora/default.nix` — verify `immich.enable = true;` is
still in the family-tier block (it should be from P8).

### 6. Rebuild

```sh
just remote aurora rebuild   # binding flips to 0.0.0.0, immich
                             # starts on the restored DB
ssh nori@aurora.saola-matrix.ts.net 'systemctl is-active immich-server'
curl -sf http://aurora.saola-matrix.ts.net:2283/api/server/ping
# {"res":"pong"} expected

just rebuild                 # workstation Caddy reproxies; local
                             # immich stops + DynamicUser dir lingers
                             # harmlessly
just remote pi rebuild       # registry consistency

curl -sk https://photos.home.phibkro.org/api/server/ping
# {"res":"pong"} via workstation Caddy → aurora tailnet IP
```

### 7. End-to-end verify

- Phone clients (Immich app) should re-prompt for login (sessions
  invalidated by the role-key change). Login succeeds, asset count
  matches.
- Admin panel → External Libraries: original `/mnt/media/photos/*`
  paths now resolve to `/mnt/family/photos/*` on aurora — verify any
  hand-imported external libraries point at paths that exist.
- Trigger a thumbnail-regen-for-one-asset action to confirm
  read+write through the migrated upload location.

## Rollback path

Restic snapshot of `/mnt/media/photos/_immich-managed` taken before
the P10 rsync covers the data; the most recent workstation
`immich-db-backup-*.sql.gz` (before stop in step 2) covers the DB. To
restore on workstation: re-enable `services.immich`, restore DB the
same way (drop + create + gunzip | psql + ownership fix), restart.

## When NOT to use this runbook

- Pre-P10 photos sync. Step 2's delta rsync assumes P10 already moved
  the bulk; running this against a fresh aurora `/mnt/family/photos`
  is hours-of-sync instead of minutes-of-delta. Wait for P10 first.
- Vectorchord-version mismatch on aurora. Verify `\dx` on both
  hosts before starting — a vchord upgrade between source and
  destination silently breaks the embeddings on restore.

## References

- `docs/superpowers/plans/2026-06-11-aurora-migration.md` § P11
- `[[postgres-ownership-after-dump-restore]]` memory entry (the
  ALTER OWNER trap)
- `modules/services/immich.nix`
- Prior cutovers: `bdda421` (vaultwarden bellwether), `ba4e49f`
  (miniflux PG migration — first time the ownership trap was caught
  in this repo)
