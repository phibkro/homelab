{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
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
