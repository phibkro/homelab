{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
    "agent"
  ];
  runtimeModule = ./nixos.nix;
  tags = [ "observability" ];
}
