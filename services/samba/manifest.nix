{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [ "network-appliance" ];
}
