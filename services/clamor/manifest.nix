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

  /*
    Clamor is realized by its own lane, not by this NixOS repository. Pi's
    Caddy reaches workstation backends through the workstation tailnet IP, so
    Clamor must listen on 0.0.0.0:4173 (the established backend pattern) or
    explicitly on workstation's tailnet address. Its loopback-only peer guard
    must also permit Pi's tailnet proxy path. The current listener and guard
    work through `tailscale serve` but cannot serve this canonical route.

    Once https://agents.home.phibkro.org is accepted off-LAN, retire the old
    workstation.saola-matrix.ts.net `tailscale serve` mapping.
  */
  endpoints.agents = {
    port = 4173;
    exposeOnTailnet = true;
    monitor = { };
    audience = "operator";
  };
}
