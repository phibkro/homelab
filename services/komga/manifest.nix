{
  active = true;
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
