{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
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
