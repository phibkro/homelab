{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "backup"
    "storage"
  ];
}
