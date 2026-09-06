{
  kind = "service";
  hostRoles = [
    "workhorse"
    "appliance"
    "agent"
  ];
  runtimeModule = ../nixos/agent.nix;
  tags = [ "observability" ];
}
