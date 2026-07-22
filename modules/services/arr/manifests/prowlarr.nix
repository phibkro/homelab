{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];

  endpoints.indexers = {
    port = 9696;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Prowlarr";
      icon = "sh:prowlarr";
      group = "Acquire";
      description = "Indexer aggregator";
    };
  };
}
