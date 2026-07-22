{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "media-reader"
    "stateful"
  ];

  endpoints.comics = {
    port = 8085;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    forwardAuth.exemptPaths = [ "/api/*" ];
    dashboard = {
      title = "Komga";
      icon = "sh:komga";
      group = "Consume";
      description = "Comics + manga + OPDS";
    };
  };
}
