{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "application-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [ "media-server" ];

  endpoints.stremio = {
    port = 11470;
    exposeOnTailnet = true;
    audience = "operator";
    monitor = { };
    dashboard = {
      title = "Stremio";
      icon = "si:stremio";
      group = "Consume";
      description = "Streaming backend (pair via web.stremio.com)";
    };
  };
}
