{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
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
