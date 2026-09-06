{
  kind = "job";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [
    "media"
    "pipeline"
  ];
}
