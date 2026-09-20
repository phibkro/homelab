{
  active = true;
  kind = "service";
  hostRoles = [ "appliance" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "entry-plane" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.tsdb = {
    port = 8428;
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
