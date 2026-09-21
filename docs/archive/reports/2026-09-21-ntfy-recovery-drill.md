# ntfy recovery drill - September 21, 2026

All times in this report are UTC. The source baseline was `f8637e1`.

## Scope

This drill tested the latest ntfy backup from the Pi. It restored the backup
into a disposable directory and started a separate ntfy container. It did not
stop, restart, or change the live ntfy service.

The drill used the deployed
`/usr/local/libexec/pi-restic-restore-disposable` helper. That helper used the
Pi's root-only Restic password, SSH key, and pinned target host key. The helper
read the `ntfy` repository from the OneTouch receiver.

## Restored snapshot

Restic restored snapshot `fffd21c6`. The snapshot was created at
`2026-09-21T01:16:37+00:00` by `root@pi`.

The restore contained eight files and directories with a total reported size
of 232.000 KiB. It included these declared paths:

- `/var/cache/ntfy`
- `/var/lib/ntfy`

Both restored SQLite databases passed `PRAGMA quick_check` with `ok`.
`cache.db` contained four tables. `user.db` contained eight tables.

The restored databases had these SHA-256 digests:

| File | SHA-256 |
|---|---|
| `cache.db` | `5f1d7725edffb09dd06af3c1cf65f2f5c6459c64c213f0f687c4a07c3c88d71c` |
| `user.db` | `ada5a009f257956267bbb7662b46f1b7ad04f0d82884b6917cbc91ff1cf7c9d4` |

## Isolated application start

The drill started a container named `ntfy-recovery-drill`. It used the same
pinned image as production:

```text
docker.io/binwiederhier/ntfy@sha256:f2419f405127afa868f10985c1a41449e673477cee1eb19994339a5ae8b592e7
```

The container used the production UID and GID, a read-only root filesystem,
dropped capabilities, and `no-new-privileges`. It mounted the restored cache
and state directories. It used the current declarative environment file because
service configuration and credentials are not part of this backup.

The restored instance listened only on `127.0.0.1:19092`. It returned this
health response:

```json
{"healthy":true}
```

The live ntfy health endpoint still returned HTTP 200 during the drill.

## Cleanup

The first two attempts stopped before application startup because the drill
user could not traverse the root-owned restore staging directory. Both attempts
left the live service unchanged. The first disposable restore was removed with
a guarded cleanup command. The second attempt used the corrected cleanup and
removed its restore automatically.

The successful run performed structural database checks as root, as the restore
helper does. The recovered application itself still ran as the production
unprivileged UID. After the successful run, the drill removed the temporary
container and restore directory. It confirmed that neither remained. The live
container remained running.

## Evidence limits

This drill proves one snapshot restore, SQLite structural integrity, application
startup, and health. It does not prove message delivery to a real subscriber,
attachment recovery, every stored data block, or every future snapshot.

The restored service still depends on current declarative configuration and
credentials. The drill did not test recovery when those inputs are unavailable.
Physical Pi reboot and off-LAN acceptance remain separate operator gates.
