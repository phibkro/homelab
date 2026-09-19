{
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "family-tier"
    "media-reader"
    "stateful"
  ];

  endpoints.photos = {
    port = 2283;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    oidc = {
      clientName = "Immich";
      redirectPath = "/auth/login";
      tokenEndpointAuthMethod = "client_secret_post";
    };
    dashboard = {
      title = "Immich";
      icon = "si:immich";
      group = "Consume";
      description = "Photo library + face recognition";
    };
  };
}
