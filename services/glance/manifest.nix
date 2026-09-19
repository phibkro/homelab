{
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { tags = [ "primary-service-host" ]; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
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
