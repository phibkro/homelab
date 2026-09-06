{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./nixos.nix;
  tags = [
    "stateful"
    "cache"
  ];

  endpoints.cache = {
    port = 5000;
    runsOn = "workstation";
    exposeOnTailnet = true;
    reachability = "internal";
    audience = "operator";
    noAuthReason = "Nix protocol clients cannot follow HTTP authentication; Attic uses signed public pulls and JWT-protected push/admin APIs.";
    monitor.path = "/nori/nix-cache-info";
  };
}
