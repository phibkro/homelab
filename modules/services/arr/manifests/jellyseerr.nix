{
  kind = "service";
  runtimeModule = ../runtime.nix;
  tags = [
    "media-server"
    "family-tier"
  ];

  endpoints.requests = {
    port = 5055;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    oidc = {
      clientName = "Jellyseerr";
      redirectPath = "/login/oidc-callback";
    };
    dashboard = {
      title = "Jellyseerr";
      icon = "sh:jellyseerr";
      group = "Acquire";
      description = "Request shows / movies (family-facing)";
    };
  };
}
