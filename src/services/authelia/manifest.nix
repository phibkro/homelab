{
  active = true;
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
  tags = [
    "network-appliance"
    "stateful"
  ];

  recovery = {
    model = "filesystem";
    backupJob = "authelia";
  };

  topology.capabilities."nori.capabilities.OidcProvider" = {
    protocol = "oidc";
  };
  endpoints.auth = {
    port = 9091;
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
