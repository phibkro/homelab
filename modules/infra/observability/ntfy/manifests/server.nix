{
  kind = "service";
  runtimeModule = ../server.nix;
  tags = [
    "network-appliance"
    "alerting"
    "stateful"
  ];

  endpoints.alert = {
    port = 8081;
    runsOn = "pi";
    monitor.path = "/v1/health";
    audience = "operator";
  };
}
