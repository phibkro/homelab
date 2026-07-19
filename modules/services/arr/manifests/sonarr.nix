{
  kind = "service";
  runtimeModule = ../runtime.nix;
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
