{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "personal-app"
    "stateless"
  ];

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
