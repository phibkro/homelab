{
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "application-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "family-tier"
    "stateful"
  ];

  topology.requires = {
    compute = {
      capability = "nori.capabilities.Compute";
      relationship = "nori.relationships.Uses";
      target = null;
      constraints.architecture.oneOf = [
        "aarch64"
        "x86_64"
      ];
    };
    persistent-storage = {
      capability = "nori.capabilities.PersistentStorage";
      relationship = "nori.relationships.Uses";
      target = null;
      constraints.class.equal = "local";
    };
    identity = {
      capability = "nori.capabilities.OidcProvider";
      relationship = "nori.relationships.AuthenticatedBy";
      target = "workload.authelia";
      constraints = { };
    };
  };

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
