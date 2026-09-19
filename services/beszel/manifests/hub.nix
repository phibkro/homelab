{
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
  runtimeModule = ../nixos/hub.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.metrics = {
    port = 8090;
    monitor.path = "/api/health";
    audience = "operator";
    oidc = {
      clientName = "Beszel";
      redirectPath = "/api/oauth2-redirect";
      tokenEndpointAuthMethod = "client_secret_basic";
    };
    dashboard = {
      title = "Beszel";
      icon = "sh:beszel";
      group = "Admin";
      description = "System metrics (CPU / RAM / disk / GPU)";
    };
  };
}
