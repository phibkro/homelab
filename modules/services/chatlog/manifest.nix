{
  kind = "service";
  hostRoles = [ "workhorse" ];
  runtimeModule = ./runtime.nix;
  tags = [
    "personal-app"
    "stateful"
  ];

  /*
    Chatlog owns its loopback-only Home Manager service and private corpus.
    This workload contributes the canonical private route plus the narrow
    tailnet relay needed by Pi's entry-plane Caddy.
  */
  endpoints.chatlog = {
    port = 4790;
    exposeOnTailnet = true;
    # The dedicated readiness endpoint validates source authority without
    # running /api/overview's multi-gigabyte dashboard aggregation.
    monitor.path = "/api/health";
    audience = "operator";
    reachability = "internal";
  };
}
