{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ../../profiles/media-acquisition/nixos.nix;
  tags = [ "media-server" ];
}
