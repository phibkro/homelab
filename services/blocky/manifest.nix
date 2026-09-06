{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
  ];
  runtimeModule = ./nixos.nix;
  tags = [ "network-appliance" ];
}
