---
name: query-logs
description: USE WHEN searching journald/service logs across the homelab — diagnosing a failed unit, looking for errors over a time range, correlating an event between services, finding when something last happened. Wraps VictoriaLogs's LogsQL HTTP API on pi:9428; agents don't need to remember the curl shape. Common patterns: errors by service, tail-like real-time follow, structured-field filter (level, unit, host), full-text grep over _msg.
---

# Query the homelab logs

VictoriaLogs aggregates every host's journald centrally on `pi`, shipped via Vector. Reachable from any tailnet device at `http://100.100.71.3:9428` (or `https://logs.nori.lan` for the web UI). The query API is `LogsQL` — terse, grep-flavored, supports stats aggregates.

## Quickest path: the Just recipe

```sh
just query-logs '<LogsQL-query>'
just query-logs 'unit:ollama.service priority:<=3 | _time:1h'
just query-logs 'level:error unit:caddy.service'
just query-logs 'parsed.path:"/health" | stats by (parsed.status) count()'
```

The recipe handles URL-encoding, points at pi automatically, and pretty-prints the JSON response.

## Direct curl (if you need raw control)

```sh
PI=100.100.71.3
curl -sG "http://$PI:9428/select/logsql/query" \
  --data-urlencode 'query=unit:ollama.service | head 20' | jq .
```

Endpoints:

| Path | Use |
|---|---|
| `/select/logsql/query` | one-shot query — returns matching records (or stats output) |
| `/select/logsql/tail` | streaming follow — like `journalctl -f` filtered by LogsQL |
| `/select/logsql/hits` | bucketed histogram for time-series viz |
| `/select/logsql/stream_ids` | list streams matching a filter (cheap discovery) |

## Field layout

Every record is JSON with these conventional fields:

| Field | Source | Example |
|---|---|---|
| `_msg` | journald message text | `time=... level=WARN msg="bad manifest"...` |
| `_time` | journal event time (`__REALTIME_TIMESTAMP`) | `2026-05-09T03:11:01.992444Z` |
| `host` | source host (stream id) | `workstation` / `pi` |
| `unit` | systemd unit (stream id) | `ollama.service` |
| `priority` | journald priority 0–7 | `3` = err, `6` = info |
| `level`, `source`, `error` | parsed from `_msg` if logfmt/JSON | `error`, `manifest.go:209`, `"failed: …"` |
| `parsed.*` | full parsed JSON/logfmt | `parsed.req_id`, `parsed.duration` |
| `_SYSTEMD_*`, `_BOOT_ID`, `_PID`, `_EXE`, `_CMDLINE` | raw journald metadata | exact systemd internals |

`_time` reflects the **actual event time** — `_time:1h` means "happened in the last hour," not "ingested in the last hour." Entries older than VictoriaLogs's `-retentionPeriod` (currently 14d on pi) are dropped at ingest as `vl_rows_dropped_total{reason="too_small_timestamp"}` rather than backfilled with skewed timestamps.

Vector preserves *everything* from journald — even when promoted to a friendly top-level name, the raw `_SYSTEMD_*` and `__*` fields are still queryable for forensic lookups.

## LogsQL cheatsheet

```
# Stream filter (cheap, uses index — prefer this over field filters when narrowing host/unit)
_stream:{host="workstation",unit="ollama.service"}

# Field filter
unit:caddy.service priority:<=3
host:workstation level:error

# Full-text grep over _msg
"connection refused"
"OOMKilled" OR "Out of memory"

# Time window — combinator after a pipe
unit:ollama.service | _time:1h
unit:ollama.service | _time:2026-06-04T08:00:00Z,2026-06-04T09:00:00Z

# Stats
unit:caddy.service | stats by (parsed.status) count()
priority:<=3 | stats by (host, unit) count()
unit:ollama.service | _time:24h | stats by (level) count()

# Pipeline (filter → select fields → limit)
unit:immich-server.service "scan" | head 50 | keep _time, _msg, level

# Negation
unit:gatus.service -priority:7  # not debug
```

## Recipe examples for common debugging shapes

**"What did X service log around time Y?"**
```sh
just query-logs 'unit:vaultwarden.service | _time:2026-06-04T03:00:00Z,2026-06-04T03:30:00Z | head 100'
```

**"Show me errors across all services last hour"**
```sh
just query-logs 'priority:<=3 | _time:1h | head 50 | keep _time, host, unit, _msg'
```

**"Count failures by unit"**
```sh
just query-logs 'priority:<=3 OR "fail" | _time:24h | stats by (unit) count()'
```

**"Tail caddy access log live"**
```sh
curl -sN "http://100.100.71.3:9428/select/logsql/tail" \
  --data-urlencode 'query=unit:caddy.service'
```

**"What did the last successful backup look like?"**
```sh
just query-logs 'unit:restic-backups-* "snapshot " | tail 5'
```

## What you can NOT do (yet)

- **No retention beyond 14 days** (or whatever `-retentionPeriod` is set on pi). Older entries are pruned at merge time.
- **No structured query before Vector parsed it.** If a service emits plain text inside `_msg`, only full-text search works on the content — `parsed.*` is empty.
- **No log-based alerting** is wired through ntfy yet. Gatus + restic `OnFailure` cover the synthetic-health side; log-pattern alerts would need a separate `services.vector` route into `alert.nori.lan`.
- **No backup of the index itself.** Pi's `@restic-local` would catch it via the future `nori.backups.victorialogs.paths` if we change the `.skip` rationale — right now it's intentionally skipped (event history is rebuild-from-zero acceptable).

## Where things live

- Pi daemon module: `modules/server/victorialogs/server.nix`
- Workstation/pi shipper: `modules/common/vector.nix`
- Caddy route + Gatus monitor + Glance entry: `modules/server/victorialogs/default.nix`
- Grafana datasource: `modules/server/grafana.nix` (`ops.nori.lan` → "VictoriaLogs")
