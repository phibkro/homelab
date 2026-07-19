{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [ "observability" ];

  endpoints.status = {
    port = 8082;
    runsOn = "pi";
    exposeOnTailnet = true;
    audience = "public";
    dashboard = {
      title = "Gatus";
      icon = "sh:gatus";
      group = "Admin";
      description = "Service uptime + alerts";
    };
  };
}
