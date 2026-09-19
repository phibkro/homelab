{
  active = true;
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
    "stateful"
    "cache"
  ];

  endpoints.cache = {
    port = 5000;
    exposeOnTailnet = true;
    reachability = "internal";
    audience = "operator";
    noAuthReason = "Nix protocol clients cannot follow HTTP authentication; Attic uses signed public pulls and JWT-protected push/admin APIs.";
    monitor.path = "/nori/nix-cache-info";
  };
}
