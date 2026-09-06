{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [ "operator-tier" ];
}
