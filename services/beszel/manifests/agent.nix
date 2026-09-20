{
  active = true;
  kind = "service";
  listeners.agent.port = 45876;
  hostRoles = [
    "workhorse"
    "appliance"
    "agent"
  ];
  placement = {
    strategy = "all-matches";
    selectors = [
      {
        roles = [
          "workhorse"
          "appliance"
        ];
      }
    ];
    cardinality = {
      min = 3;
      max = 3;
    };
  };
  runtimeModule = ../nixos/agent.nix;
  tags = [ "observability" ];
}
