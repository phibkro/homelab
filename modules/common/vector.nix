{ config, ... }:

{
  # Vector — journald → VictoriaLogs shipper, replacing systemd-journal-
  # upload (the previous incumbent at modules/common/journal-upload.nix,
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
          .unit = .SYSTEMD_UNIT
          .pid = .PID
          .priority = .PRIORITY
          # Preserve the journal's original timestamp under a separate
          # field for forensic queries, then bump `.timestamp` (the
          # field VictoriaLogs reads via `_time_field`) to NOW so the
          # default retention window doesn't drop replayed entries on
          # ingest. Trade-off: queries by time return ingest-time, not
          # journal-time. Acceptable while the retention window is
          # short — pivot to journal-time once pi's retention is set
          # to cover the full journal horizon.
          .journal_timestamp = .timestamp
          .timestamp = now()
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
