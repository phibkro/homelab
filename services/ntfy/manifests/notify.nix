{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  placement = {
    strategy = "all-matches";
    selectors = [
      { host = "pi"; }
      { host = "workstation"; }
    ];
    cardinality = {
      min = 2;
      max = 2;
    };
  };
  runtimeModule = ../nixos/notify.nix;
  tags = [
    "observability"
    "alerting"
  ];
}
