{ config, lib, ... }:

# VictoriaMetrics — single-binary metrics database. Lives on the
# appliance host (pi) for the same fate-sharing reason as VictoriaLogs:
# observability infra shouldn't go down with the host being observed.
# When workstation hangs, the metrics history that might explain why
# has to live somewhere that's still up.

lib.mkMerge [
  {
    nori.services.victoriametrics.tags = [
      "observability"
      "stateful"
    ];

    # Caddy lanRoute on workstation: metrics.nori.lan is taken by
    # Beszel's hub. Park the VM query UI under a function-name that
    # signals "TSDB" rather than competing with Beszel's branding.
    # Operator-only audience (tailnet auth perimeter) — the VM web UI
    # is admin tooling, never a family-tier surface.
    nori.lanRoutes.tsdb = {
      port = 8428;
      runsOn = "pi";
      monitor.path = "/health";
      audience = "operator";
      dashboard = {
        title = "VictoriaMetrics";
        icon = "si:victoriametrics";
        group = "Admin";
        description = "TSDB query UI — backs the unified Grafana dashboard.";
      };
    };
  }
  (lib.mkIf config.nori.services.victoriametrics.enabled {
    services.victoriametrics = {
      enable = true;
      listenAddress = ":8428";
      # `prometheusConfig` takes the structured attrset, NOT a YAML
      # string or file path. The NixOS module serialises this to JSON
      # (which VM also accepts) and passes the resulting path via
      # -promscrape.config. Passing a path here would write the path
      # STRING into the file, not the YAML content, and VM rejects it
      # with "cannot unmarshal !!str into promscrape.Config".
      prometheusConfig = {
        global = {
          scrape_interval = "30s";
          scrape_timeout = "10s";
        };
        scrape_configs = [
          {
            job_name = "gatus-workstation";
            metrics_path = "/metrics";
            scheme = "http";
            static_configs = [
              {
                targets = [ "${config.nori.hosts.workstation.tailnetIp}:8082" ];
                labels.host = "workstation";
              }
            ];
          }
          {
            job_name = "gatus-pi";
            metrics_path = "/metrics";
            scheme = "http";
            static_configs = [
              {
                targets = [ "${config.nori.hosts.pi.tailnetIp}:8082" ];
                labels.host = "pi";
              }
            ];
          }
          # System + per-process metrics from each host's node-exporter
          # and process-exporter (modules/services/node-exporter.nix).
          # Single static_configs block per kind, one label per target,
          # so the {host=...} dimension carries the dispatch.
          {
            job_name = "node";
            metrics_path = "/metrics";
            scheme = "http";
            static_configs = [
              {
                targets = [ "${config.nori.hosts.workstation.tailnetIp}:9100" ];
                labels.host = "workstation";
              }
              {
                targets = [ "${config.nori.hosts.pavilion.tailnetIp}:9100" ];
                labels.host = "pavilion";
              }
              {
                targets = [ "${config.nori.hosts.aurora.tailnetIp}:9100" ];
                labels.host = "aurora";
              }
            ];
          }
          {
            job_name = "process";
            metrics_path = "/metrics";
            scheme = "http";
            static_configs = [
              {
                targets = [ "${config.nori.hosts.workstation.tailnetIp}:9256" ];
                labels.host = "workstation";
              }
              {
                targets = [ "${config.nori.hosts.pavilion.tailnetIp}:9256" ];
                labels.host = "pavilion";
              }
              {
                targets = [ "${config.nori.hosts.aurora.tailnetIp}:9256" ];
                labels.host = "aurora";
              }
            ];
          }
          # GPU power + utilisation from nvidia-gpu-exporter (modules/
          # services/nvidia-gpu-exporter.nix). Only hosts with NVIDIA
          # devices run the exporter; pavilion + pi silently absent.
          {
            job_name = "nvidia-gpu";
            metrics_path = "/metrics";
            scheme = "http";
            static_configs = [
              {
                targets = [ "${config.nori.hosts.workstation.tailnetIp}:9835" ];
                labels.host = "workstation";
              }
              {
                targets = [ "${config.nori.hosts.aurora.tailnetIp}:9835" ];
                labels.host = "aurora";
              }
            ];
          }
        ];
      };
      extraOptions = [
        # Two-week retention — enough for "what happened last weekend?"
        # without unbounded growth on Pi's flash.
        "-retentionPeriod=14d"
      ];
    };

    # Tailnet firewall: Grafana on workstation queries via this; LAN
    # exposure is via Caddy on workstation (lanRoute below).
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      8428
    ];

    nori.harden.victoriametrics = { };
    nori.backups.victoriametrics.skip = "Event-history scratch on Pi flash; same anti-write posture as VictoriaLogs.";
  })
]
