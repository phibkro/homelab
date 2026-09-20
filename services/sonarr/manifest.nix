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

  endpoints.tv = {
    port = 8989;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Sonarr";
      icon = "si:sonarr";
      group = "Acquire";
      description = "TV show automation";
    };
  };
}
