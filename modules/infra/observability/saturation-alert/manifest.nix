{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
    "agent"
  ];
  runtimeModule = ./runtime.nix;
  tags = [ "observability" ];
}
