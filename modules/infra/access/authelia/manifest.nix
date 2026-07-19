{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "network-appliance"
    "stateful"
  ];
  endpoints.auth = {
    port = 9091;
    runsOn = "pi";
    monitor = { };
    audience = "public";
    dashboard = {
      title = "Authelia";
      icon = "sh:authelia";
      group = "Admin";
      description = "OIDC SSO issuer";
    };
  };
}
