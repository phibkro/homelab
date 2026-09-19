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
  tags = [ "observability" ];
}
