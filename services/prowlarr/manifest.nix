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
  runtimeModule = ../../profiles/media-acquisition/nixos.nix;
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
