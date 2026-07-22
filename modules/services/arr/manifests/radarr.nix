{
  kind = "service";
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];

  endpoints.movies = {
    port = 7878;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
    dashboard = {
      title = "Radarr";
      icon = "si:radarr";
      group = "Acquire";
      description = "Movie automation";
    };
  };
}
