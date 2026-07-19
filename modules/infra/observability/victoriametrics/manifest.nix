{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.tsdb = {
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
