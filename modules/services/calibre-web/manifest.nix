{
  kind = "service";
  runtimeModule = ./runtime.nix;
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
