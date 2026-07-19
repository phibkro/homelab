{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "personal-app"
    "stateless"
  ];

  endpoints.filmder = {
    port = 9092;
    exposeOnTailnet = true;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Filmder";
      icon = "si:themoviedatabase";
      group = "Projects";
      description = "TMDB-backed movie browser (uni project, 2023)";
    };
  };
}
