# Immich export recovery drill — September 21, 2026

This drill proved the application-native database export path for Immich. It
used source revision `b98344216dc7`. Times are UTC unless specified otherwise.

## Scope

Immich runs on the workstation. Its live PostgreSQL database stays on the root
NVMe. Immich creates compressed SQL exports in:

`/mnt/media/photos/_immich-managed/backups`

That path is inside the `media-irreplaceable` Restic repository. The drill
restored one export, imported it into a disposable PostgreSQL cluster, and
compared database counts with production. It did not stop or write the
production Immich or PostgreSQL services.

## Application export

Immich started its scheduled database export at 00:00:00 and reported success
at 00:00:20. The export was:

`immich-db-backup-20260921T020000-v3.1.0-pg17.11.sql.gz`

The file was 82,064,498 bytes. `gzip -t` accepted the compressed stream.
Immich produced the export with PostgreSQL 17.11.

## Fresh snapshot and selective restore

The normal `restic-backups-media-irreplaceable-onetouch.service` unit completed
successfully at 00:59:23. Restic created snapshot `4ec23eef` at 00:58:59.

The restore selected only the Immich database export from the complete media
snapshot. Restic restored one file with 78.263 MiB of compressed data. The
restored file and source file had the same SHA-256 digest:

`5d014660ce6e0da934f503ca5d61172578b93e74b35a3da6f79721db50eb3916`

## Isolated PostgreSQL import

The restored export was imported into a new PostgreSQL 17.11 cluster. The
cluster used the deployed PostgreSQL package and `vchord.so` preload setting.
It ran in a private network namespace, exposed no TCP listener, and used a
private Unix socket.

The SQL client used `ON_ERROR_STOP=1`. All 1,066 command-result lines completed
without an import error. The expanded database size was 302,044,851 bytes.

The restored database loaded these extensions:

- `cube` 1.5;
- `earthdistance` 1.2;
- `pg_trgm` 1.6;
- `plpgsql` 1.0;
- `unaccent` 1.1;
- `uuid-ossp` 1.1;
- `vchord` 1.1.1;
- `vector` 0.8.6.

## Database state

| Relation | Production before drill | Restored export |
|---|---:|---:|
| Users | 1 | 1 |
| Assets | 14,402 | 14,402 |
| Albums | 71 | 71 |
| Libraries | 0 | 0 |

The counts matched production at the time of the drill. This establishes that
the scheduled export, Restic snapshot, selective restore, PostgreSQL import,
and extension set form one usable recovery path.

## Cleanup and production check

The disposable PostgreSQL server stopped before its private namespace exited.
The restored export, database cluster, socket, and logs were removed. The
production Immich and PostgreSQL services remained active. The production
Immich `/api/server/ping` endpoint returned HTTP 200 after cleanup.

## Evidence boundary

This drill establishes the application-native export path:

```text
Immich scheduled SQL export → media-irreplaceable snapshot
                            → selective restore
                            → isolated PostgreSQL import
```

It does not establish:

- Immich startup against the restored database;
- login, album browsing, or asset retrieval from the restored database;
- recovery of original photos, thumbnails, profiles, or encoded videos;
- media-file and database consistency at one atomic point in time;
- production database replacement;
- complete workstation reconstruction;
- every-file data-block integrity for the media repository.

The next recovery stage should cover user data or media metadata. A complete
Immich recovery must pair this database export with the matching managed media
snapshot and then exercise the application journey.
