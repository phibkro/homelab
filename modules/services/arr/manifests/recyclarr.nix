{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../runtime.nix;
  tags = [ "media-server" ];
}
