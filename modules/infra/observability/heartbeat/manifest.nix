{
  kind = "service";
  hostRoles = [ "appliance" ];
  runtimeModule = ./runtime.nix;
  tags = [ "observability" ];
}
