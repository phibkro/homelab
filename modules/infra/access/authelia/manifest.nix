let
  site = import ../../../../inventory/site.nix;
in
{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "network-appliance"
    "stateful"
  ];
  endpoints.auth = {
    port = 9091;
    runsOn = site.entryPlaneHost;
    monitor.path = "/api/health";
    audience = "public";
    dashboard = {
      title = "Authelia";
      icon = "sh:authelia";
      group = "Admin";
      description = "OIDC SSO issuer";
    };
  };
}
