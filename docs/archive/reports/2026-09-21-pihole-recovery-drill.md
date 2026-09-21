# Pi-hole recovery drill — September 21, 2026

This drill proved that Pi-hole can start from a current OneTouch snapshot and
serve recovered DNS state. It used source revision `e8cc5a94af71`. Times are
UTC unless specified otherwise.

## Scope

The drill used the existing `pihole` backup job from `inventory/backup.nix`.
That job contains:

- the Pi-hole data volume under `/var/lib/containers/storage/volumes/pihole-data/_data`;
- the generated local DNS records file under `/opt/pihole/dnsmasq.d`.

The existing disposable restore helper used the pinned SFTP transport and its
root-only credentials. It wrote only below `/var/lib/pi-restic-restore`.

A temporary Podman container used the same pinned Pi-hole image as production.
It published DNS and HTTP only on loopback ports `18053` and `18081`. It used a
new temporary volume and a throwaway web password.

The drill did not stop or change the production container or its volume.

## Destination and capacity gates

The mounted destination matched the inventory declaration:

| Property | Observed value |
|---|---|
| Device | `/dev/sdb1` mounted read/write at `/mnt/backup` |
| Model | `One Touch HDD` |
| Serial | `00000000NABNR6G2` |
| Filesystem | `ext4`, label `onetouch-backup` |
| Pi free space before restore | 19 GiB |
| Initial latest restore size | 83.993 MiB |

The exact pinned Pi-hole image already existed on the Pi. The drill did not
pull another image.

## Snapshot selection

The first `latest` restore selected snapshot `a9f07f54` from September 20 at
01:20:39 UTC. Its generated records differed from the live records because the
source configuration had changed after that snapshot.

The normal `pi-restic-backup-pihole.service` job then completed successfully at
00:28:19 UTC. A second `latest` restore selected snapshot `c7b2308e`, created at
00:28:14 UTC. The restore produced 42 files and directories with a total size
of 86.679 MiB. Its generated records matched the live source byte-for-byte.

This sequence shows why backup freshness and configuration equality are
separate gates. The application test used only snapshot `c7b2308e`.

## Application result

The temporary container copied the restored data into its temporary volume
before startup. The restored DNS records directory was mounted read-only.

| Check | Result |
|---|---|
| Container state | `running` |
| Web endpoint | HTTP `302` from `/admin/` |
| Restored local record | `workstation.home.phibkro.org` returned `192.168.1.181` |
| Restored block data | `doubleclick.net` returned `0.0.0.0` |
| `gravity.db` integrity | `PRAGMA integrity_check` returned `ok` |
| Enabled adlists | 1 |
| Gravity domains | 76,230 |

Pi-hole startup recovered 357 frames from the restored FTL database write-ahead
log. The service then initialized the database and served DNS. This proves that
this snapshot was usable. It does not prove that every raw live SQLite snapshot
will be consistent. Pi-hole has no logical SQLite preparation hook.

## Cleanup and production check

The temporary container, temporary volume, and both new restore directories
were removed. The exact cleanup names started with `pihole-recovery-` or were
below `/var/lib/pi-restic-restore/pihole-`.

The production `pihole` container remained `running` on the pinned image. After
cleanup, a production DNS query for `doubleclick.net` still returned `0.0.0.0`.

## Evidence boundary

This drill establishes one current, consumer-visible Pi-hole recovery path:
OneTouch snapshot to disposable restore, then restored state to a running
application and DNS result.

It does not establish:

- the files, logical SQLite, PostgreSQL, or service-export recovery models as a
  complete set;
- user-data or media recovery;
- every-file data-block integrity;
- production replacement or host reconstruction;
- physical reboot or off-LAN behavior;
- recovery of Pi-hole credentials or authenticated administration.

The next state-model drills should use Vaultwarden for logical SQLite,
Miniflux for PostgreSQL, and an application with a native export for the
service-export model. Those drills must remain isolated from production.
