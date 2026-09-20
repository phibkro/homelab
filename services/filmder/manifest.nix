{
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
      reason = "Filmder has no published immutable package; the selected workhorse builds the reviewed upstream branch into an atomic local static tree.";
      removalTrigger = "Filmder publishes a pinned flake package or checksummed release archive containing the static site.";
      verification = "tests/eval/product-artifacts.nix";
    };
  };

  endpoints.filmder = {
    port = 9092;
    exposeOnTailnet = true;
    audience = "family";
    forwardAuth.exemptPaths = [ ];
    monitor = { };
    dashboard = {
      title = "Filmder";
      icon = "si:themoviedatabase";
      group = "Projects";
      description = "TMDB-backed movie browser (uni project, 2023)";
    };
  };
}
