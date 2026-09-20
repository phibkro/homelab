{
  active = true;
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
      { host = "adelie"; }
    ];
    cardinality = {
      min = 3;
      max = 3;
    };
  };
  runtimeModule = ../nixos/notify.nix;
  tags = [
    "observability"
    "alerting"
  ];
}
