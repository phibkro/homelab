{
  kind = "service";
  runtimeModule = ../hub.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.metrics = {
    port = 8090;
    runsOn = "pi";
    monitor = { };
    audience = "operator";
    oidc = {
      clientName = "Beszel";
      redirectPath = "/api/oauth2-redirect";
    };
    dashboard = {
      title = "Beszel";
      icon = "sh:beszel";
      group = "Admin";
      description = "System metrics (CPU / RAM / disk / GPU)";
    };
  };
}
