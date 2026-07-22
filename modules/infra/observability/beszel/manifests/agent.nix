{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
    "agent"
  ];
  runtimeModule = ../agent.nix;
  tags = [ "observability" ];
}
