{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
    "agent"
  ];
  placement = {
    strategy = "all-matches";
    selectors = [ { tags = [ "nixos" ]; } ];
    cardinality = {
      min = 2;
      max = 2;
    };
  };
  runtimeModule = ./nixos.nix;
  listeners = {
    node.port = 9100;
    process.port = 9256;
  };
  tags = [ "observability" ];
}
