{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  runtimeModule = ../nixos/notify.nix;
  tags = [
    "observability"
    "alerting"
  ];
}
