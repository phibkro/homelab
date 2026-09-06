{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ./nixos.nix;
  tags = [
    "network-appliance"
    "stateful"
  ];
}
