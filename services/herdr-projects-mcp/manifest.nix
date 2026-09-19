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
    "operator-tier"
    "stateful"
  ];

  endpoints.projects-origin = {
    port = 9081;
    exposeOnTailnet = true;
    reachability = "internal";
    audience = "operator";
  };
}
