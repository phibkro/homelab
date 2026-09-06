{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [ "observability" ];
}
