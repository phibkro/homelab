{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "personal-app"
    "stateless"
  ];

  artifact = {
    kind = "static-web";
    immutable = false;
    source = {
      repository = "https://github.com/phibkro/heim.git";
      ref = "main";
    };
    consumer = {
      kind = "legacy-host-build";
      unit = "heim-build";
    };
    legacyException = {
      owner = "homelab operator";
      reason = "Heim has no published immutable package or release archive yet; Aurora builds the reviewed upstream branch into an atomic local static tree.";
      removalTrigger = "Heim publishes a pinned flake package or checksummed release archive containing the static site.";
      verification = "tests/eval/product-artifacts.nix";
    };
  };

  endpoints.heim = {
    port = 9094;
    exposeOnTailnet = true;
    audience = "public";
    monitor = { };
    dashboard = {
      title = "Heim";
      icon = "si:astro";
      group = "Projects";
      description = "Operator's portfolio (Astro, markdown-authored)";
    };
  };
}
