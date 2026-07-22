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

  endpoints.status = {
    port = 8082;
    runsOn = site.entryPlaneHost;
    exposeOnTailnet = true;
    audience = "public";
    dashboard = {
      title = "Gatus";
      icon = "sh:gatus";
      group = "Admin";
      description = "Service uptime + alerts";
    };
  };
}
