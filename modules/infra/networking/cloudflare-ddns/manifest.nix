{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "network-appliance"
    "stateless"
  ];
}
