{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "family-tier"
    "media-server"
    "stateful"
  ];

  endpoints.manga = {
    port = 8088;
    exposeOnTailnet = true;
    monitor = { };
    audience = "family";
    forwardAuth.exemptPaths = [ "/api/*" ];
    dashboard = {
      title = "Suwayomi";
      icon = "sh:suwayomi";
      group = "Acquire";
      description = "Manga downloader (Tachiyomi sources)";
    };
  };
}
