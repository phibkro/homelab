---
name: gotcha-nixpkgs-downgrade-strands-state
description: USE WHEN pinning nixpkgs BACKWARDS (e.g. unstable → stable, or one stable → an older stable) — newer packages typically write state in formats older versions can't read; the state survives the rebuild and breaks the service start. Pre-pin: list `/var/lib/<svc>/` services + diff package versions + check forward-back compat. Cache-class state = wipe; load-bearing state = forward-and-back dump-restore.
---

# Downgrading nixpkgs can strand persistent state from newer package versions

Pinning nixpkgs **backwards** (e.g. unstable → stable) downgrades package versions in lock-step. Newer software typically writes its state in formats older versions can't read — and unlike read-only configs, on-disk state survives the rebuild and breaks the service start. Same shape as the well-known Postgres-major-version-downgrade trap, but it bites smaller packages too.

Hit 2026-06-03 when pinning nixos-unstable → nixos-26.05:

- Redis dropped from 9.x (unstable) → 8.6.3 (stable 26.05).
- `redis-immich.service` failed to start with:
  ```
  Can't handle RDB format version 14
  Fatal error loading the DB, check server logs. Exiting.
  ```
- RDB v14 is the format Redis 9.x writes; 8.6.3 only reads v13 and below.

**Recovery** for cache-class state (Immich's Redis is just session/queue cache — photos + metadata live in Postgres + filesystem):

```sh
sudo systemctl stop redis-immich.service
sudo mv /var/lib/redis-immich/dump.rdb /var/lib/redis-immich/dump.rdb.vNEW-backup
sudo systemctl start redis-immich.service
# Then restart anything that depends on it:
sudo systemctl restart immich-server immich-machine-learning
```

For services where the state **isn't** disposable (Postgres data, Vaultwarden vault, Authelia user db), the recovery is structurally different — you'd need to roll **forward** again temporarily (`nix flake update` to a newer revision), `pg_dumpall` (or analogue), then come back to stable and `pg_restore` against a fresh data dir. A simple `rm` deletes user data.

**Before pinning backwards:**

1. List every service with persistent state under `/var/lib/<service>/`.
2. For each, check whether the package version changes between source and target nixpkgs (`nix eval '<flake>#nixosConfigurations.<host>.config.services.<svc>.package.version'` against both lock states).
3. Anything that changed: either confirm forward-and-back compat from upstream release notes, or plan a dump-restore.

Diagnostics:

- Check the failing unit's journal for "format version" or "version mismatch" — usually the explicit signal.
- `file /var/lib/<svc>/<state-file>` sometimes identifies the writer version.
- Each service has its own state format guarantees; consult upstream's downgrade policy specifically.
