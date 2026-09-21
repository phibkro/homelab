# Pi service recovery closure - September 21, 2026

All times are UTC. The source baseline was `e64c74d`.

## Scope

This pass closed the autonomous application and repository-integrity boundaries
for all eight Pi backup jobs declared by `inventory/backup.nix`. Each application
restore used `/usr/local/libexec/pi-restic-restore-disposable`. Recovered
services used loopback-only listeners or validation commands. The live services
were not stopped or changed.

## Application recovery

### Caddy

Restic restored snapshot `75b31c0e`, created at
`2026-09-21T01:17:03+00:00`. It restored 22 files and directories from
`/opt/caddy/data` and `/opt/caddy/config`, totaling 23.118 KiB.

The production Caddy image validated the current declarative Caddyfile while
using the restored data and configuration mounts. Validation returned
`Valid configuration`. The restored state occupied 23,673 bytes. A TLS request
to the live Caddy entry plane for `media.home.phibkro.org` returned HTTP 302,
the Jellyfin root redirect.

### Beszel

Restic restored snapshot `c26dcf22`, created at
`2026-09-21T01:15:49+00:00`. It restored ten files and directories from
`/var/lib/beszel`, totaling 5.992 MiB.

The restored PocketBase SQLite database passed `PRAGMA quick_check` with `ok`
and contained 24 tables. An isolated container used the production image and
restored state. Its `/api/health` response reported code 200 and
`API is healthy.`

### VictoriaMetrics

Restic restored snapshot `64e294af`, created at
`2026-09-21T01:16:33+00:00`. It restored 515 files and directories from
`/var/lib/victoriametrics` and `/etc/victoriametrics`, totaling 319.934 MiB.

An isolated container used the production image, restored TSDB, and restored
scrape configuration. `/health` returned `OK`. An instant `up` query returned a
successful API response. No current series matched because the isolated process
had no time to scrape production targets.

### VictoriaLogs and Vector

Restic restored VictoriaLogs snapshot `c3319c0b`, created at
`2026-09-21T01:26:34+00:00`. It restored 61,435 files and directories from
`/var/lib/victorialogs`, totaling 165.367 MiB.

An isolated container used the production image and restored log database.
`/health` returned `OK`. A bounded LogsQL query returned HTTP 200.

Restic restored Vector snapshot `c98494d7`, created at
`2026-09-21T01:15:49+00:00`. It restored eight files and directories from
`/var/lib/vector` and `/etc/vector`, totaling 1.431 KiB. The drill rewrote only
the disposable configuration's sink and API addresses. The production Vector
image validated that configuration and returned `{"ok":true}` from its isolated
health endpoint. Its sink targeted only the isolated VictoriaLogs instance.

## Full repository data verification

The pass ran a one-time `restic check --read-data` through the deployed pinned
Pi transport for every declared repository. Every snapshot tree and every data
pack was read.

| Repository | Snapshots checked | Packs read | Result |
|---|---:|---:|---|
| `pihole` | 9 | 20 | no errors |
| `caddy` | 19 | 18 | no errors |
| `authelia` | 20 | 17 | no errors |
| `ntfy` | 8 | 13 | no errors |
| `beszel` | 8 | 13 | no errors |
| `victoriametrics` | 8 | 35 | no errors |
| `victorialogs` | 8 | 24 | no errors |
| `vector` | 8 | 14 | no errors |

This is stronger than the scheduled weekly metadata check and monthly ten
percent data subset. It is a dated observation, not a permanent guarantee.

## Safety and cleanup

The successful drill confirmed that the live Caddy, Beszel, VictoriaMetrics,
VictoriaLogs, and Vector containers remained running. It removed every
disposable container and restore directory.

Three preliminary Caddy validation attempts failed before any other recovered
service started. The first used restrictions that prevented the image entry
point from executing. The second lacked the Cloudflare environment input. The
third used obsolete or unavailable status hostnames for the live check. Each
attempt cleaned its restored directory. The successful attempt passed the
existing production token to the validator without printing it and checked the
canonical media route through the local entry plane.

## Limits

This pass does not prove physical Pi replacement, off-LAN access, interactive
Beszel OIDC login, historical query completeness, or every future snapshot.
Caddy still depends on the current declarative Caddyfile and Cloudflare token.
The recovered observability services used current immutable images. Vector
configuration was modified only in the disposable copy to prevent writes to the
live VictoriaLogs service.

Pi has no declared user-data or media backup job. Workstation user-data and
media recovery remain separate contracts. Physical power-cycle and off-LAN
acceptance remain operator IOUs.
