{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "operator-tier"
    "stateful"
  ];

  /*
    The Control Plane deliberately has no endpoint: it stays on loopback and
    is published only by an operator-owned Tailscale Serve mapping.

    Publish only the bearer-checking MCP proxy through the shared workstation
    Cloudflare Tunnel. The Hindsight REST API and web UI remain loopback-only.
  */
  endpoints.memory-origin = {
    port = 9078;
    exposeOnTailnet = true;
    reachability = "internal";
    audience = "operator";
    noAuthReason = "Cloudflare's MCP portal supplies a dedicated static bearer token; browser-cookie and OIDC gates are not MCP transports";
  };
}
