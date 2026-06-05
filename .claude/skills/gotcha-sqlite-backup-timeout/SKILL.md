---
name: gotcha-sqlite-backup-timeout
description: USE WHEN writing a `nori.backups.<svc>.prepareCommand` (Pattern C2) that runs `sqlite3 .backup` on a live service's database, OR when a `restic-backups-*` unit fails with `Error: database is locked`. Pass `.timeout 30000` BEFORE the `.backup` dot-command so sqlite3 waits up to 30s for the write lock instead of failing immediately. Without it any in-flight write at backup o'clock kills the unit.
---

# `sqlite3 .backup` against a live service needs `.timeout`

## Symptom

A `restic-backups-<svc>` unit fails on the pre-start sqlite dump step:

```
restic-backups-<svc>-pre-start[NNNNN]: Error: database is locked
restic-backups-<svc>.service: Control process exited, code=exited, status=1/FAILURE
```

Service runs fine, prior days' backups succeeded, no obvious cause.

## Root cause

`sqlite3 <db> ".backup '<dest>'"` returns `database is locked` the **instant** a writer holds the SQLite lock. SQLite has a built-in busy-handler that can wait, but its default timeout in the `sqlite3` CLI is **zero** — fail immediately.

Most homelab services using Pattern C2 do small but frequent writes:
- Vaultwarden writes on every sync/login.
- Open WebUI's scheduler-worker polls every 10s and logs chat completions.
- Navidrome scrobbles + scans the library.

Any of these can land mid-write at the nightly backup tick (04:00–04:45 by default in this homelab) and trigger the race.

## Fix

Pass `.timeout 30000` (30 seconds, milliseconds units) as a dot-command **before** `.backup`:

```nix
prepareCommand = ''
  if [ -f /var/lib/<svc>/<db>.sqlite3 ]; then
    mkdir -p /var/backup/<svc>
    ${pkgs.sqlite}/bin/sqlite3 /var/lib/<svc>/<db>.sqlite3 \
      ".timeout 30000" \
      ".backup '/var/backup/<svc>/<db>.sqlite3'"
  fi
'';
```

30s is a deliberate middle ground: long enough that any normal write completes (single-user services), short enough that a real deadlock surfaces via the existing OnFailure → ntfy alert without burning the whole backup window.

## Where this applies (as of 2026-06-05)

All Pattern C2 SQLite services in `modules/server/`:
- `vaultwarden.nix`
- `open-webui.nix`
- `navidrome.nix`

Pattern A (filesystem-only) and Pattern B (built-in dump) backups are unaffected — no live SQLite `.backup` step. Pattern C1 (Postgres via `services.postgresqlBackup`) uses pg_dump which has its own locking model and doesn't need this fix.

## Don't go higher than 30s without a real reason

If a service's writes regularly take longer than 30s to clear, the right fix is either to redesign the backup window or stop the service briefly. A 5-minute SQLite timeout would mask real backup window problems — better to fail loudly via the existing OnFailure → ntfy chain so the operator can see the pattern.
