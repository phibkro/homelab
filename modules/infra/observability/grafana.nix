{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkMerge [
  {
    nori.services.grafana.tags = [
      "observability"
      "stateful"
    ];

    nori.lanRoutes.ops = {
      port = 3000;
      runsOn = "aurora";
      exposeOnTailnet = true;
      audience = "operator";
      monitor.path = "/api/health";
      dashboard = {
        title = "Ops";
        icon = "si:grafana";
        group = "Admin";
        description = "Cross-source dashboards over logs + metrics.";
      };
    };
  }
  (lib.mkIf config.nori.services.grafana.enabled {
    /*
      Grafana's settings file is rendered into /run from Nix at activation
      — secrets in the rendered file would leak via /nix/store-readability
      if interpolated directly. Use Grafana's $__file{path} placeholder
      so the secret is read at process start from a sops-managed path
      instead. NixOS 26.05 removed the legacy default for `secret_key`;
      without an explicit value, eval fails (catches the silent-default
      foot-gun documented in the upstream changelog).
    */
    sops.secrets.grafana-secret-key = {
      owner = "grafana";
      mode = "0400";
    };

    /**
      Grafana — operator's cross-source observability console at
      `ops.nori.lan`. Distinct from Glance (`home.nori.lan`, family-facing
      landing) and Beszel (`metrics.nori.lan`, single-source telemetry
      native UI). Grafana's role here is the join — VictoriaLogs LogsQL
      + (future) VictoriaMetrics time-series in one queryable view, with
      operator-owned dashboards committed alongside the rest of the
      flake config.

      Provisioned declaratively from this module — datasources via
      services.grafana.provision.datasources, dashboards from
      ./grafana-dashboards/. The Grafana DB at /var/lib/grafana still
      accumulates session-scoped state (last-viewed dashboard, query
      history) but the *configuration* lives in the flake. UI-side
      dashboard edits land in the DB and get overridden on restart —
      the discipline is to export edited dashboards to JSON in the
      repo, not to keep them as in-DB state. (Same pattern Stylix
      uses for theming: declarative source of truth, no UI-state drift.)

      Auth: anonymous-Admin on the tailnet. audience = "operator" means
      tailnet membership IS the auth perimeter; layering Authelia on top
      of a single-operator admin tool duplicates the network-perimeter
      guarantee for no gain. The qBittorrent precedent.
    */

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
          /*
            Caddy terminates TLS at ops.<nori.domain> and proxies here;
            tell Grafana the public URL so its self-generated links
            don't point at 127.0.0.1.
          */
          root_url = "https://ops.${config.nori.domain}/";
          enforce_domain = false;
        };

        "auth.anonymous" = {
          enabled = true;
          org_role = "Admin";
          org_name = "Main Org.";
        };
        auth = {
          # Hide the login page entirely; anonymous-Admin makes it
          # vestigial and confusing.
          disable_login_form = true;
          disable_signout_menu = true;
        };

        # Reduce noise from Grafana's own polling/version checks.
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
          check_for_plugin_updates = false;
        };

        security.secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
      };

      # Declarative plugins rather than Grafana's plugin manager (the
      # manager downloads at runtime → not reproducible).
      declarativePlugins = with pkgs.grafanaPlugins; [
        victoriametrics-logs-datasource
        victoriametrics-metrics-datasource
      ];

      provision = {
        enable = true;
        /*
          Delete the auto-UID copy of VictoriaMetrics from the running
          Grafana DB so the provisioned `uid = "victoriametrics"` below
          can take over. Without this, provisioning fails on a name
          conflict (same name + different uid), the dashboard's
          `uid: victoriametrics` reference resolves to "not found", and
          grafana exits 1 on start. This entry is idempotent — after the
          first restart the orphan is gone; the directive becomes a
          no-op but stays for documentation.
        */
        datasources.settings.deleteDatasources = [
          {
            name = "VictoriaMetrics";
            orgId = 1;
          }
        ];
        datasources.settings.datasources = [
          {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://${config.nori.hosts.pi.tailnetIp}:9428";
            isDefault = true;
            jsonData.timeout = 60;
          }
          {
            name = "VictoriaMetrics";
            /*
              Stable UID so provisioned dashboards under ./grafana-
              dashboards/ can reference this datasource by uid without
              having to discover the auto-generated value at runtime.
              The Gatus dashboard (./grafana-dashboards/gatus.json)
              uses this exact uid.
            */
            uid = "victoriametrics";
            /*
              Native Prometheus-compatible API — Grafana's built-in
              `prometheus` datasource type works as-is, no plugin needed.
              (The dedicated victoriametrics-datasource plugin adds VM-
              specific features; not required for our queries today.)
            */
            type = "prometheus";
            access = "proxy";
            url = "http://${config.nori.hosts.pi.tailnetIp}:8428";
            isDefault = false;
            jsonData.timeInterval = "30s"; # matches the scrape interval
          }
        ];

        dashboards.settings.providers = [
          {
            name = "Default";
            folder = "Lab";
            options.path = ./grafana-dashboards;
            updateIntervalSeconds = 60;
            # Subdir = UI folder; nest as the dashboard set grows.
            foldersFromFilesStructure = true;
          }
        ];
      };
    };

    /*
      Default-deny FS namespace. Grafana writes its sqlite DB + log file
      under /var/lib/grafana (handled by the upstream module's
      StateDirectory). The harden binds make it explicit; without
      writable /var/lib/grafana the service would fail to start.
    */
    nori.harden.grafana = {
      binds = [ "/var/lib/grafana" ];
    };

    # Re-evaluate if alerts-as-code accrue useful firing-history state.
    nori.backups.grafana.skip = "Provisioned from flake (datasources + dashboards); DB holds only session-scoped state.";
  })
]
