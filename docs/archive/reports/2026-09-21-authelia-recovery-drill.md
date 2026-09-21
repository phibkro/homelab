# Authelia recovery drill - September 21, 2026

All times in this report are UTC. The source baseline was `ccf8984`.

## Scope

This drill tested the latest Authelia backup from the Pi. It restored the
backup into a disposable directory and started a separate Authelia container.
It did not stop, restart, or change the live Authelia service.

The drill used the deployed
`/usr/local/libexec/pi-restic-restore-disposable` helper. That helper used the
Pi's root-only Restic password, SSH key, and pinned target host key. The helper
read the `authelia` repository from the OneTouch receiver.

## Restored snapshot

Restic restored snapshot `fc2b5b8b`. The snapshot was created at
`2026-09-21T01:27:39+00:00` by `root@pi`.

The restore contained nine files and directories with a total reported size of
306.933 KiB. It included these declared paths:

- `/etc/authelia/configuration.yml`
- `/etc/authelia/users_database.yml`
- `/var/lib/authelia`

The restored SQLite database passed `PRAGMA quick_check` with `ok`. Its schema
contained 26 tables.

The restored files had these SHA-256 digests:

| File | SHA-256 |
|---|---|
| `configuration.yml` | `9ae3de7ae6cc20371189907e387367814a3293bb86df675e0442527cb32e55b0` |
| `users_database.yml` | `3155ef5f1d02099794c863a2090e050934bb7f09d415277e09c7001a6cfad2a0` |
| `db.sqlite3` | `68aa784f0ad59b8b5bd9b0e46415ce5eaf1aeb963580243f2771c8cb5979c21b` |

## Isolated application start

The drill started a container named `authelia-recovery-drill`. It used the
same pinned image as production:

```text
ghcr.io/authelia/authelia@sha256:1b363e9279e742397966333f364e0876ae02bf5c876de73e83af6d48c57ff51b
```

The container used the production UID and GID, read-only root filesystem,
dropped capabilities, and `no-new-privileges`. It mounted the restored
configuration and state. It mounted the current declarative secret directory
read-only because secrets are not part of the backup.

The drill overrode only the listener. It published the restored instance on
`127.0.0.1:19091`. No public or tailnet listener was created.

The restored instance returned this health response:

```json
{"status":"OK"}
```

OIDC discovery returned the canonical issuer and authorization endpoint:

```text
issuer=https://auth.home.phibkro.org
authorization_endpoint=https://auth.home.phibkro.org/api/oidc/authorization
```

The request included the same HTTPS proxy headers that Caddy supplies. A first
request without those headers returned HTTP 400. The restored health endpoint
had already passed, and the failed attempt cleaned up its container and restore
directory. The second isolated run passed all gates.

The live Authelia health endpoint still returned HTTP 200 during the drill.

## Cleanup

The drill removed the temporary container and its restored directory. It then
confirmed that neither remained. The live container remained running.

## Evidence limits

This drill proves one snapshot restore, SQLite structural integrity, application
startup, health, and OIDC discovery. It does not prove an interactive login,
token exchange, preserved session validity, every stored data block, or every
future snapshot.

The restored service still depends on the current declarative secret files.
The drill did not test recovery when those inputs are unavailable. Physical Pi
reboot and off-LAN acceptance remain separate operator gates.
