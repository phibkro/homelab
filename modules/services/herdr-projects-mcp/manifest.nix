{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
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
