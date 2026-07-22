{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  runtimeModule = ./runtime.nix;
  tags = [ "network-appliance" ];
}
