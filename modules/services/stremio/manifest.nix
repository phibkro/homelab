{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
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
