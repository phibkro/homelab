{ config, lib, ... }:

lib.mkMerge [
  {
    nori.services.victorialogs-server.tags = [
      "observability"
      "stateful"
    ];
  }
  (lib.mkIf config.nori.services.victorialogs-server.enabled {
    /**
      VictoriaLogs — single-binary log database (events + logs). Daemon
      lives on the appliance host (pi): observability infra shouldn't
      share fate with the host being observed. When workstation hangs,
      the record of what it was doing right before the hang has to live
      somewhere that's still up.

      Wide-events convention: every event ingested should carry
      `version`, `service`, and `host` fields so queries stay useful as
      the schema evolves.

      State at /var/lib/private/victorialogs (DynamicUser, upstream
      module). Treated as ephemeral — Pi's flash storage is anti-write
      (machines/pi/hardware.nix), log data is event-history, and the
      alert path (ntfy + Gatus) is independent of this index. Revisit
      if/when Pi gains a real disk.
    */

    services.victorialogs = {
      enable = true;
      listenAddress = ":9428";
      extraOptions = [
        /*
          Two-week wall: long enough to catch a vacation-length absence,
          short enough that retention pressure on pi's flash stays bounded.
          Doubles as the ingest-time drop threshold — rows older than
          `now - retentionPeriod` get dropped at the door (drop counter:
          vl_rows_dropped_total{reason="too_small_timestamp"}). Bites
          journal-upload's first-run backfill, which streams from the
          start of the local journal; reset its cursor (rm the state
          file at /var/lib/private/systemd-journal-upload/state then
          restart the unit) when that happens — `/var/lib/systemd/
          journal-upload/state` if DynamicUser is off.
        */
        "-retentionPeriod=14d"
        /*
          Hard disk cap (40% of pi's 128 GiB FIT = ~50 GiB). Belt to the
          retentionPeriod's suspenders — if log volume spikes, the disk
          bound takes over before the time bound does. Both must be
          present (intent + safety); -retentionPeriod alone wouldn't
          protect pi's flash from a runaway producer.
        */
        "-retention.maxDiskUsagePercent=40"
      ];
    };

    nori.harden.victorialogs = { };

    # Cross-host: station's Caddy hits Pi's tailnet IP on :9428.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 9428 ];

    nori.backups.victorialogs.skip = "Daemon on appliance host (pi). Flash anti-write posture + non-load-bearing event history; alert path (ntfy + Gatus) is independent of this index.";
  })
]
