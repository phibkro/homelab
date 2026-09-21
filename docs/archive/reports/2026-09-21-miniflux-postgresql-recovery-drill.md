# Miniflux PostgreSQL recovery drill — September 21, 2026

This drill proved the PostgreSQL recovery path for Miniflux. It used source
revision `dcd625dd1d8e`. Times are UTC unless specified otherwise.

## Scope

Miniflux runs on Adelie and stores all application state in PostgreSQL. Its
backup declaration requires `postgresqlBackup-miniflux.service` before each
Restic run. PostgreSQL writes a compressed logical dump with `--no-owner` to
`/var/backup/postgresql/miniflux.sql.gz`.

The drill used the deployed Restic transport and its pinned workstation host
identity. It restored the latest OneTouch snapshot into a new directory on
Adelie. It did not stop or write the production Miniflux or PostgreSQL service.

## Fresh snapshot and restore

The normal PostgreSQL dump completed successfully at 00:45:38. The dependent
`restic-backups-miniflux-onetouch.service` unit completed at 00:45:44. The
compressed dump size was 133,811 bytes.

Restic selected snapshot `dfa999c5`, created at 00:45:41. It restored four
files and directories with a total size of 130.675 KiB. The snapshot contained
the current compressed logical dump.

## Isolation and import

The drill created a new PostgreSQL `17.11` data directory. PostgreSQL and
Miniflux ran in one private Linux network namespace. Only its loopback
interface was enabled. The processes could not contact Authelia, feeds, the
internet, or another host.

The restore sequence was:

1. Initialize a new PostgreSQL cluster with trust limited to the private
   namespace.
2. Create a new `miniflux` role and database.
3. Decompress and import the dump with `ON_ERROR_STOP` enabled.
4. Query the restored application tables.
5. Start the deployed Miniflux `2.3.3` binary against the restored database.
6. Verify the real HTTP health and application endpoints.

No production credential or environment file was loaded.

## Application and database result

| Check | Result |
|---|---|
| PostgreSQL import | Completed without SQL errors |
| Restored users | 2 |
| Restored feeds | 4 |
| Restored entries | 189 |
| Schema migration | Current version `132`; latest version `132` |
| Miniflux startup | Listening on `127.0.0.1:18087` |
| `/healthcheck` | HTTP `200` |
| `/` | HTTP `200` |
| Row counts after startup | Unchanged |

The restored service read the imported database without changing the user,
feed, or entry counts. This establishes logical dump import, schema validity,
application startup, and consumer-visible HTTP behavior.

## Cleanup and production check

The temporary Miniflux process and PostgreSQL cluster stopped before cleanup.
The restore directory, temporary cluster, sockets, logs, and response files
were removed. Ports `15432` and `18087` had no listeners after cleanup.

The production PostgreSQL and Miniflux services remained active. The production
Miniflux `/healthcheck` endpoint returned HTTP `200` after the drill.

## Evidence boundary

This drill establishes the PostgreSQL state model:

```text
live PostgreSQL → pg_dump → Restic snapshot → disposable restore
                → new PostgreSQL cluster → real Miniflux process
```

It does not establish:

- password or OIDC login;
- feed refresh over the network;
- correctness of article contents beyond restored row counts;
- production database replacement;
- files-only or native-export recovery;
- complete Adelie host reconstruction;
- every-file data-block integrity for all repositories.

The next state-model drills should cover a plain files-only service and an
application-native export. User-data, media, and complete host recovery remain
separate later stages.
