{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "media-reader"
    "stateful"
  ];

  endpoints.audio = {
    port = 4533;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    oidc = {
      clientName = "Navidrome";
      redirectPath = "/auth/callback";
      secretEnvName = "ND_AUTH_OIDC_CLIENTSECRET";
    };
    dashboard = {
      title = "Navidrome";
      icon = "sh:navidrome";
      group = "Consume";
      description = "Subsonic-protocol music streaming";
    };
  };
}
