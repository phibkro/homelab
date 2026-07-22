{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "personal-app"
    "stateless"
  ];

  artifact = {
    kind = "static-web";
    immutable = false;
    source = {
      repository = "https://github.com/phibkro/filmder.git";
      ref = "main";
    };
    consumer = {
      kind = "legacy-host-build";
      unit = "filmder-build";
    };
    legacyException = {
      owner = "homelab operator";
      reason = "Filmder currently embeds its TMDB credential during the Vite build, so a hermetic public artifact cannot carry the production configuration.";
      removalTrigger = "Filmder publishes an immutable package or release artifact whose TMDB integration accepts runtime configuration without embedding the production credential.";
      verification = "tests/eval/product-artifacts.nix";
    };
  };

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
