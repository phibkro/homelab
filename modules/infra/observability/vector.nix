{ config, ... }:

{
  # Vector — journald → VictoriaLogs shipper, replacing systemd-journal-
  # upload (the previous incumbent at modules/common/journal-upload.nix,  # path-coherence: skip — historical
  # since deleted). The /insert/journald path in VictoriaLogs 1.50.0
  # silently dropped every row as `too_small_timestamp` despite
  # journal-upload sending correct microsecond `__REALTIME_TIMESTAMP`
  # fields — suspected wire-format/unit-conversion bug; multiple hours
  # of debugging didn't yield a fix. Vector's Elasticsearch sink against
  # VictoriaLogs's `/insert/elasticsearch/_bulk` is upstream's
  # recommended integration path and is what the manual jsonline
  # control-test (count(*) > 0) confirmed working end-to-end.
  #
  # Same fate-independence rationale as everything else that ships to
  # pi: workstation is the producer, pi is the durable observer.
  # Direct tailnet HTTP to pi:9428, NOT via Caddy — write-path
  # shouldn't traverse Caddy (would make Caddy a SPoF for ingest;
  # human-facing UI at https://logs.nori.lan stays via Caddy).
  #
  # Pi ships its own journald too. Pi-to-pi over loopback-via-tailnet
  # works fine and is the easiest way to keep pi's own service
  # transitions visible in the central index.

  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      # journald source — Vector reads from systemd-journald directly.
      # current_boot_only=false so first-run picks up the existing
      # journal (subject to retentionPeriod on the VictoriaLogs side).
      sources.journald = {
        type = "journald";
        current_boot_only = false;
      };

      # Promote a few stream-identity fields to top-level names so the
      # VictoriaLogs query syntax stays terse. VictoriaLogs treats the
      # fields listed in `_stream_fields=` as the stream identity; the
      # rest become queryable columns.
      transforms.relabel = {
        type = "remap";
        inputs = [ "journald" ];
        source = ''
          # Trusted systemd fields are prefixed with `_` in Vector's
          # journald output (user-set fields are bare). Promote a few
          # to friendly top-level names so query syntax stays short.
          .unit = ._SYSTEMD_UNIT
          .pid = ._PID
          .priority = .PRIORITY
          # `.timestamp` (which VictoriaLogs reads via _time_field) is
          # Vector's journald source mapping of __REALTIME_TIMESTAMP —
          # i.e. the event's actual journal time, not ingest time. Pass
          # it through unmodified so `_time:1h`-style LogsQL queries are
          # truthful. Trade-off: on first ingest, entries older than
          # the retention window (currently 14d, set on pi at
          # modules/infra/observability/victorialogs/server.nix) get silently dropped
          # by VictoriaLogs as `too_small_timestamp`. Widen retention if
          # we want deeper backfill queryable.

          # ── Inner-message parsing ──────────────────────────────────
          # Many NixOS services emit logfmt or JSON inside the journald
          # `.message` payload (ollama uses logfmt; caddy emits JSON;
          # the Go ecosystem leans logfmt; Python apps vary). Parse on
          # a best-effort basis: try JSON first (cheap to fail), fall
          # back to logfmt. Whatever sticks lands under `.parsed`,
          # with a handful of high-frequency fields promoted to
          # top-level for terse query syntax (`level:error` reads
          # better than `parsed.level:error`).
          #
          # Errors are silently ignored — a plaintext logger isn't a
          # bug, it just doesn't yield parsed fields.
          msg = to_string(.message) ?? ""
          if starts_with(msg, "{") {
            parsed, err = parse_json(msg)
            if err == null { .parsed = parsed }
          }
          if !exists(.parsed) && contains(msg, "=") {
            parsed, err = parse_logfmt(msg)
            if err == null && length(parsed) > 1 { .parsed = parsed }
          }

          # Promote a small, conventional set. Adding more here grows
          # column cardinality on the indexdb side — keep it tight.
          if exists(.parsed.level)  { .level  = .parsed.level }
          if exists(.parsed.lvl)    { .level  = .parsed.lvl   }
          if exists(.parsed.source) { .source = .parsed.source }
          if exists(.parsed.caller) { .source = .parsed.caller }
          if exists(.parsed.error)  { .error  = .parsed.error  }
          if exists(.parsed.err)    { .error  = .parsed.err    }
        '';
      };

      # VictoriaLogs's /insert/elasticsearch/_bulk endpoint is the
      # battle-tested Vector integration per upstream docs. The
      # `query` parameters tell VictoriaLogs which fields to map to
      # the special _stream / _msg / _time slots.
      sinks.vlogs = {
        type = "elasticsearch";
        inputs = [ "relabel" ];
        endpoints = [ "http://${config.nori.hosts.pi.tailnetIp}:9428/insert/elasticsearch" ];
        mode = "bulk";
        api_version = "v8";
        healthcheck.enabled = false;
        query = {
          _msg_field = "message";
          _time_field = "timestamp";
          _stream_fields = "host,unit";
        };
      };
    };
  };
}
