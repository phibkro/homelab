{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.logs = {
    port = 9428;
    runsOn = "pi";
    monitor.path = "/health";
    audience = "operator";
  };
}
