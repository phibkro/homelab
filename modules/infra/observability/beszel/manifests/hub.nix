let
  site = import ../../../../../inventory/site.nix;
in
{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ../hub.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.metrics = {
    port = 8090;
    runsOn = site.entryPlaneHost;
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
