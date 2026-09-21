# Stremio files recovery drill — September 21, 2026

This drill proved a files-only recovery path for Stremio. It used source
revision `d251ecbd1d94` before the cache-exclusion correction described below.
Times are UTC unless specified otherwise.

## Scope

Stremio runs on Adelie. Its persistent identity consists of:

- `server-settings.json`, which stores server settings;
- `httpsCert.json`, which stores the server pairing certificate.

The same state directory also contained 2.2 GiB of streaming cache. Cache data
is re-downloadable and is not required to recover the server identity.

The drill used the deployed Restic transport and its pinned workstation host
identity. It did not stop or write the production Stremio service.

## Fresh snapshot and restore

The normal `restic-backups-stremio-onetouch.service` unit completed
successfully at 00:52:05. Restic selected snapshot `d22c546f`, created at
00:52:02.

The disposable restore selected only the two persistent identity files from
the snapshot. It restored 8.159 KiB. Both files matched the live source
byte-for-byte before application startup.

## Isolation

The restored service ran in private network and mount namespaces. Only the
network namespace's loopback interface was enabled. A private bind mount placed
the restored directory at `/var/lib/stremio` inside the mount namespace.

The mount namespace was necessary because `server-settings.json` records the
canonical application path. Network isolation alone would not prevent the
process from opening the production path. The private bind mount made that bad
state unavailable to the temporary process.

The temporary process used the deployed Node.js runtime and pinned Stremio
Server `4.20.12` bundle. It ran as the `stremio` system user without a
production service restart.

## Application result

| Check | Result |
|---|---|
| Restored files | 2 |
| Restored bytes | 8,355 |
| Root endpoint | HTTP `307`, the normal Stremio application redirect |
| `/settings` | HTTP `200` |
| Reported server version | `4.20.12` |
| Restored remote HTTPS identity | `100.81.5.122`, equal to production |
| Reported application path | `/var/lib/stremio`, backed by the private mount |

After the temporary service stopped, both production identity files still
matched the restored snapshot byte-for-byte. This confirms that the drill did
not alter production state.

## Backup correction

The source declaration previously backed up the complete Stremio state
directory. This included 2.2 GiB of streaming cache despite a comment that the
directory was tiny.

`services/stremio/nixos.nix` now excludes
`/var/lib/stremio/stremio-cache`. Future snapshots will retain the pairing
certificate and server settings without retaining re-downloadable stream
chunks. This source change requires the next Adelie activation before it
changes the deployed backup unit. Existing snapshots remain intact.

## Cleanup and production check

The temporary process, mount namespace, restore directory, response files, and
logs were removed. The production Stremio service remained active. Its root
and `/settings` endpoints returned HTTP `307` and `200` after cleanup.

## Evidence boundary

This drill establishes the files-only state model:

```text
identity files → Restic snapshot → selected disposable restore
               → private mount → real Stremio process
```

It does not establish:

- client re-pairing;
- video playback or transcoding;
- recovery of streaming cache, which is intentionally excluded;
- production replacement;
- an application-native export recovery;
- complete Adelie host reconstruction;
- every-file data-block integrity for all repositories.

The remaining state-model gap is an application-native export. User-data,
media, and complete host recovery remain separate later stages.
