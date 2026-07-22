let
  site = import ../../../../inventory/site.nix;
in
{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.tsdb = {
    port = 8428;
    runsOn = site.entryPlaneHost;
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
