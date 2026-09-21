# Jellyfin metadata recovery drill — September 21, 2026

This drill proved isolated startup from restored Jellyfin service metadata. It
used source revision `7a8c5711d5b4`. Times are UTC unless specified otherwise.

## Scope

Jellyfin stores its library index, users, watch state, configuration, images,
and logs under `/var/lib/jellyfin`. Media files remain on separate storage and
are not part of the Jellyfin service-state repository.

The drill created a fresh snapshot, restored the complete service state, checked
the SQLite database, and started the deployed Jellyfin binary against the
restored state. It did not stop or write the production Jellyfin service.

## Fresh snapshot and restore

The normal `restic-backups-jellyfin-onetouch.service` unit completed
successfully at 01:26:49. Restic created snapshot `7ecaedf5` at 01:26:45.

The disposable restore recovered 17,404 files and directories with 1.393 GiB
of logical data.

## Database validation

The restored `jellyfin.db` was 30,523,392 bytes. SQLite
`PRAGMA integrity_check` returned `ok` before and after application startup.

| Relation | Production before drill | Restored snapshot | Restored after startup |
|---|---:|---:|---:|
| Library items | 7,254 | 7,254 | 7,254 |
| Users | 1 | 1 | 1 |
| User data rows | 841 | 841 | 841 |
| Activity rows | 1,298 | 1,298 | 1,298 |

The restored counts matched production at the time of the drill.

## Isolated application startup

The deployed Jellyfin `12.0.0` binary ran as the `jellyfin` user in private
network and mount namespaces. A private bind mount placed the restored state at
`/var/lib/jellyfin`. A disposable cache replaced `/var/cache/jellyfin`.

The namespace exposed only its loopback interface. Empty temporary filesystems
masked `/mnt/media` and `/srv/share`. The temporary process could not reach the
network or inspect production media files.

Jellyfin performs a short setup-server phase before the main server becomes
ready. The drill waited until the public API reported the restored
`StartupWizardCompleted` value instead of treating the first HTTP response as
final readiness.

| Check | Result |
|---|---|
| `/health` | HTTP `200` |
| `/System/Info/Public` | HTTP `200` |
| Product | `Jellyfin Server` |
| Version | `12.0.0` |
| Startup wizard complete | `true` |
| Network interfaces | loopback only |
| Visible production media entries | 0 |
| Visible production share entries | 0 |

## Cleanup and production check

The temporary Jellyfin process stopped before its private namespaces exited.
The restored state, disposable cache, API response, and logs were removed.

The production Jellyfin service remained active. Its `/health` endpoint
returned HTTP 200. Its public API reported Jellyfin `12.0.0` with the startup
wizard complete. The production database integrity check still returned `ok`,
and its row counts were unchanged.

## Evidence boundary

This drill establishes the media-metadata path:

```text
Jellyfin state → fresh OneTouch snapshot → complete disposable restore
               → SQLite integrity check → isolated Jellyfin API startup
```

It does not establish:

- authenticated login or library browsing from the restored instance;
- playback, transcoding, thumbnails, or media-file readability;
- recovery of the separate media files;
- atomic consistency between metadata and media files;
- an atomic SQLite snapshot while the production service is live;
- production state replacement;
- complete workstation reconstruction;
- every-file data-block integrity for all repositories.

The database used WAL mode. No WAL frames were pending during the preflight,
and the restored database passed integrity checks and real application startup.
A live filesystem snapshot can still race a later write. The stronger future
model is a SQLite-native prepared copy if Jellyfin metadata becomes
non-rebuildable or more valuable.

The next recovery stage is complete host reconstruction.
