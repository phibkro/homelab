{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  endpoints.vault = {
    port = 8222;
    exposeOnTailnet = true;
    monitor.path = "/alive";
    audience = "family";
    oidc = {
      clientName = "Vaultwarden";
      redirectPath = "/identity/connect/oidc-signin";
      tokenEndpointAuthMethod = "client_secret_basic";
      secretEnvName = "SSO_CLIENT_SECRET";
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
        "offline_access"
      ];
    };
  };
}
