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

  endpoints.books = {
    port = 8084;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    forwardAuth.exemptPaths = [
      "/opds/*"
      "/kobo/*"
      "/api/*"
    ];
    dashboard = {
      title = "calibre-web";
      icon = "sh:calibre-web";
      group = "Consume";
      description = "Ebook reader + OPDS";
    };
  };
}
