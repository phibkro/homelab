{
  kind = "service";
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];

  endpoints.music = {
    port = 8686;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Lidarr";
      icon = "sh:lidarr";
      group = "Acquire";
      description = "Music automation";
    };
  };
}
