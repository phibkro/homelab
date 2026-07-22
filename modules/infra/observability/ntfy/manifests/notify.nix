{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  runtimeModule = ../notify.nix;
  tags = [
    "observability"
    "alerting"
  ];
}
