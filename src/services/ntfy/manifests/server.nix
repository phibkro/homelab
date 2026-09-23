{
  active = true;
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
  runtimeModule = ../nixos/server.nix;
  tags = [
    "network-appliance"
    "alerting"
    "stateful"
  ];

  recovery = {
    model = "filesystem";
    backupJob = "ntfy";
  };

  endpoints.alert = {
    port = 8091;
    monitor.path = "/v1/health";
    audience = "operator";
  };
}
