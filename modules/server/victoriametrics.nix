{ config, pkgs, ... }:

# VictoriaMetrics — single-binary metrics database, sibling of
# VictoriaLogs. Lives on the appliance host (pi) for the same fate-
# sharing reason: observability infra shouldn't go down with the host
# being observed. When workstation hangs, the metrics history that
# might explain why has to live somewhere that's still up.
#
# Listens on :8428 (VM's default — distinct from VictoriaLogs on
# :9428). Scraped targets:
#   - workstation gatus → /api/v1/metrics (uptime/probe state)
#   - pi gatus           → same
# Future scrape targets (Tier B): node_exporter on each host.
#
# Surfaced to Grafana on workstation via a datasource pointing at
# this Pi instance — see modules/server/grafana.nix.
#
# State at /var/lib/private/victoriametrics (DynamicUser via the
# upstream module). Same anti-write posture as VictoriaLogs — Pi's
# flash storage is treated as ephemeral; retention bounded so
# pressure stays manageable.

let
  prometheusConfig = pkgs.writeText "victoriametrics-scrape.yml" ''
    global:
      scrape_interval: 30s
      scrape_timeout: 10s

    scrape_configs:
      - job_name: gatus-workstation
        metrics_path: /api/v1/metrics
        scheme: http
        static_configs:
          - targets:
              - ${config.nori.hosts.workstation.tailnetIp}:8082
            labels:
              host: workstation

      - job_name: gatus-pi
        metrics_path: /api/v1/metrics
        scheme: http
        static_configs:
          - targets:
              - ${config.nori.hosts.pi.tailnetIp}:8082
            labels:
              host: pi
  '';
in
{
  services.victoriametrics = {
    enable = true;
    listenAddress = ":8428";
    prometheusConfig = prometheusConfig;
    extraOptions = [
      # Two-week retention — enough for "what happened last weekend?"
      # without unbounded growth on Pi's flash. Matches VictoriaLogs.
      "-retentionPeriod=14d"
    ];
  };

  # Tailnet firewall: open the scrape/query port for tailnet clients
  # (Grafana on workstation queries via this). LAN exposure is via
  # Caddy on workstation, declared as a lanRoute below.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8428
  ];

  # Caddy lanRoute on workstation: metrics.nori.lan is taken by
  # Beszel's hub. Park the VM query UI under a function-name that
  # signals "TSDB" rather than competing with Beszel's branding.
  # Operator-only audience (tailnet auth perimeter) — the VM web UI
  # is admin tooling, never a family-tier surface.
  nori.lanRoutes.tsdb = {
    port = 8428;
    host = config.nori.hosts.pi.tailnetIp;
    monitor.path = "/health";
    audience = "operator";
    dashboard = {
      title = "VictoriaMetrics";
      icon = "si:victoriametrics";
      group = "Admin";
      description = "TSDB query UI — backs the unified Grafana dashboard.";
    };
  };

  # No on-disk state to back up — VM here is event-history scratch
  # (same posture as VictoriaLogs on this host); Pi flash is anti-
  # write. If retention ever moves to a real disk, revisit.
  nori.backups.victoriametrics.skip =
    "Event-history scratch on Pi flash; same anti-write posture as VictoriaLogs.";
}
