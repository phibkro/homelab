{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ./nixos.nix;
  tags = [ "observability" ];
}
