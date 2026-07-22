{
  kind = "job";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "media"
    "pipeline"
  ];
}
