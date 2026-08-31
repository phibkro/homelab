{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints.news = {
    port = 8087;
    exposeOnTailnet = true;
    monitor.path = "/healthcheck";
    audience = "family";
    oidc = {
      clientName = "Miniflux";
      redirectPath = "/oauth2/oidc/callback";
      tokenEndpointAuthMethod = "client_secret_basic";
      secretEnvName = "OAUTH2_CLIENT_SECRET";
    };
  };
}
