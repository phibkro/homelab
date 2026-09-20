{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "application-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.ops = {
    port = 3000;
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
