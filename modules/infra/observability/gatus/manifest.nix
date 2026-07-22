let
  site = import ../../../../inventory/site.nix;
in
{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  runtimeModule = ./runtime.nix;
  tags = [ "observability" ];

  endpoints.uptime = {
    port = 8082;
    runsOn = site.entryPlaneHost;
    exposeOnTailnet = true;
    audience = "operator";
    dashboard = {
      title = "Gatus";
      icon = "sh:gatus";
      group = "Admin";
      description = "Service uptime + alerts";
    };
  };
}
