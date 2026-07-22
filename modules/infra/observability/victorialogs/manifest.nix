let
  site = import ../../../../inventory/site.nix;
in
{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.logs = {
    port = 9428;
    runsOn = site.entryPlaneHost;
    monitor.path = "/health";
    audience = "operator";
  };
}
