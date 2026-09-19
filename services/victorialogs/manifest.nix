{
  kind = "service";
  hostRoles = [ "appliance" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "entry-plane" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "observability"
    "stateful"
  ];

  endpoints.logs = {
    port = 9428;
    monitor.path = "/health";
    audience = "operator";
  };
}
