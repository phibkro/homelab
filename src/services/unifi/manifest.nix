{
  active = true;
  kind = "service";
  hostRoles = [ "workhorse" ];
  placement = {
    strategy = "first-unique";
    selectors = [ { host = "workstation"; } ];
    cardinality = {
      min = 1;
      max = 1;
    };
  };
  runtimeModule = ./nixos.nix;
  tags = [
    "network-appliance"
    "stateful"
  ];
  recovery = {
    model = "application-export";
    backupJob = "unifi";
  };

  # No endpoint: the controller UI stays on the private tailnet listener and
  # does not create a Caddy route, DNS record, or external authentication client.
  # Reserve every controller port in inventory to catch local collisions.
  listeners = {
    inform.port = 8080;
    # Tailscale Serve already owns 8443 on this host.
    ui.port = 7443;
    portal-http.port = 8880;
    portal-https.port = 8843;
    portal-https-proxy.port = 8444;
    throughput.port = 6789;
    database.port = 27117;
    stun.port = 3478;
    discovery.port = 10001;
    redirector.port = 8881;
    redirector-wired.port = 8882;
  };
}
