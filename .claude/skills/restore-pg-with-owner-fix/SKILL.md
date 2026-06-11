---
name: restore-pg-with-owner-fix
description: USE WHEN restoring a service's gzipped postgres dump into a freshly-empty database during a workstation→aurora cutover (P11) or any cross-host pg migration — `psql <db> < dump` run as the postgres superuser leaves every table owned by `postgres`, breaks the service that reads its own `schema_version` under its service role (miniflux, immich, …), and restart-loops with `relation "schema_version" already exists (42P07)`. This skill runs drop + recreate + restore + the `ALTER OWNER` sweep across all tables + sequences + the public schema in one shot, so the trap doesn't bite a second time.
---

# Restore a postgres dump with the ownership fix baked in

## When this skill applies

You're migrating a postgres-backed service between hosts and have a
gzipped dump (`.sql.gz`) on the target. Typical sources:

- `services.postgresqlBackup` output at
  `/var/backup/postgresql/<svc>.sql.gz` — `pgdumpOptions = "--no-owner"`
  is the homelab default
- A service's own self-dump
  (immich: `/mnt/family/photos/_immich-managed/backups/immich-db-backup-*.sql.gz`)
- An ad-hoc `pg_dump <db> | gzip > /tmp/<db>.sql.gz`

You want the destination database owned by the service role
(`miniflux`, `immich`, …), not by `postgres` — otherwise the service
silently fails to read its own schema-version sentinel and
restart-loops.

## The trap, once more, in one line

`psql <db> < dump.sql` run as `postgres` makes every CREATE inherit
`postgres` ownership — the service role can SELECT (via grants) but
not ALTER, so the migration runner sees an empty `schema_version`
state, tries to `CREATE TABLE schema_version`, hits the existing one,
exits 1. Systemd restart-loops it.

Full background: `[[postgres-ownership-after-dump-restore]]` memory.

## Run it

```sh
sudo bash .claude/skills/restore-pg-with-owner-fix/restore.sh \
  <db> <role> <path/to/dump.sql.gz>
```

Three positional args:

- `<db>` — destination database name (e.g. `miniflux`, `immich`).
  Will be dropped + recreated.
- `<role>` — postgres role that should own everything (typically the
  same as `<db>`). Must already exist (declared by the service's NixOS
  module via `services.<svc>.user` / `ensureUsers`).
- `<path/to/dump.sql.gz>` — gzipped pg dump file. Readable by root.

The script:

1. Verifies the dump is readable and the role exists.
2. `dropdb --if-exists <db>` and `createdb -O <role> <db>`.
3. `gunzip -c <dump> | psql <db>` (running as postgres).
4. Reassigns ownership of every table + sequence + the `public` schema
   to `<role>` (the trap fix).
5. Prints the first few rows of `\dt` so you can confirm the owner
   column.

After it completes successfully, start the service. The migration
runner will see the correct `schema_version` and exit cleanly.

## What this skill is NOT

- **Not a generic pg restore**. It assumes `public` schema, default
  ownership model, gzipped dump. Custom-format dumps (`pg_restore`),
  multi-schema setups, or per-role grant patterns need different
  surgery.
- **Not a cross-version safety net**. Restoring a pg17 dump into a
  pg14 cluster won't work; both hosts must be on a compatible major
  version. Verify with `\dx` on both hosts before starting
  (especially extension versions — vchord, vector, etc.).
- **Not for live data**. The drop+recreate destroys whatever's in the
  destination DB. The cutover pattern is: stop the service, restore
  fresh, start the service. Don't run this with anyone connected.

## Why a skill rather than a `just` recipe

Surface-area + discoverability tradeoff. `just --list` is for
day-to-day operator workflows; this script is only useful during the
rare pg-migration window. A skill keeps it out of the operator's
mental cache until the agent's trigger phrase (cross-host pg
migration / dump+restore) matches, while the script itself stays
runnable directly if needed.

## References

- `[[postgres-ownership-after-dump-restore]]` — full rationale of the
  trap and why the `--no-owner` default in `services.postgresqlBackup`
  produces it
- `docs/runbooks/immich-cutover.md` — the runbook that calls this
  skill for the heaviest pg migration in the aurora plan
- `ba4e49f` — the miniflux cutover commit where the trap was first
  caught in this repo
