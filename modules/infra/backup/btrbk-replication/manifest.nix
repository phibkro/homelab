{
  kind = "service";
  runtimeModule = ./runtime.nix;
  tags = [
    "backup"
    "replication"
  ];
}
