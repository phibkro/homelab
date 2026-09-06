{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [
    "family-tier"
    "stateless"
  ];

  endpoints.home = {
    port = 8086;
    exposeOnTailnet = true;
    monitor = { };
    audience = "public";
  };
}
