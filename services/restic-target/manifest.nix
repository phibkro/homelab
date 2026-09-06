{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [
    "backup"
    "storage"
  ];
}
