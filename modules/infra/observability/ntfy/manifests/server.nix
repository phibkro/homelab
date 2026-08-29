let
  site = import ../../../../../inventory/site.nix;
in
{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ../server.nix;
  tags = [
    "network-appliance"
    "alerting"
    "stateful"
  ];

  endpoints.alert = {
    port = 8091;
    runsOn = site.entryPlaneHost;
    monitor.path = "/v1/health";
    audience = "operator";
  };
}
