{ config, lib, ... }:

lib.mkMerge [
  {
    nori.services.caddy.tags = [
      "network-appliance"
      "stateful"
    ];
  }
  (lib.mkIf config.nori.services.caddy.enabled {
    # Caddy reverse proxy — clean *.nori.lan subdomain per service,
    # HTTPS via Caddy's internal CA.
    #
    # Per-device root cert install (one-time, auto-generated at
    # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt):
    #
    #   # Mac:
    #   sudo security add-trusted-cert -d -r trustRoot \
    #     -k /Library/Keychains/System.keychain root.crt
    #
    #   # iOS: AirDrop the cert → Settings → Profile install → Settings
    #   # → General → About → Certificate Trust Settings → toggle on
    #   # for "Caddy Local Authority"
    #
    # DNS path: Blocky's customDNS (modules/services/blocky.nix) maps
    # each *.nori.lan to workstation's LAN IP. LAN clients hit Caddy
    # directly; off-LAN tailnet clients reach the same address via
    # Pi's subnet route advertisement (192.168.1.0/24, needs
    # --accept-routes on the client).

    services.caddy = {
      enable = true;
      # Use Caddy's internal CA for all sites (no ACME / public DNS
      # dance). The `auto_https disable_redirects` keeps Caddy from
      # silently installing http→https redirects on port 80 we don't
      # want. `local_certs` switches every vhost's automatic HTTPS to
      # the internal CA. Trust install is disabled via systemd env var
      # below — devices install the root cert manually anyway.
      globalConfig = ''
        local_certs
      '';

      # Virtual hosts are NOT defined here. They're auto-generated from
      # `nori.lanRoutes.<name>` declarations in each service's own
      # module — see modules/effects/lan-route.nix for the option +
      # generator. Adding/renaming a route happens at the source
      # (the service module), not here.
    };

    # Skip the system trust install attempt; the hardened service can't
    # write to /etc/ssl/... and there's no point anyway since we install
    # the root cert per-device manually.
    systemd.services.caddy.environment.CADDY_AUTO_TRUST = "0";

    nori.harden.caddy = { };

    # Open globally, not per-interface: with `*.nori.lan` resolving to
    # the workhorse LAN IP (`nori.lanIp` in modules/effects/lan-route.nix),
    # requests arrive on the LAN interface for LAN clients and on
    # tailscale0 for off-LAN tailnet clients via Pi's subnet route. Same
    # precedent as Blocky's :53. The router doesn't forward :80/:443
    # inbound from WAN, so the host firewall is just the second layer.
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    # Add Caddy's internal root CA to the system trust store so other
    # services on this host (Open WebUI's Python httpx fetching OIDC
    # discovery, future Gatus probes through Caddy URLs, anything
    # using libcurl/openssl/python-requests) trust the certs Caddy
    # issues for *.nori.lan. The cert here is the public half of
    # Caddy's auto-generated CA — pull a fresh copy from
    # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
    # if Caddy ever regenerates it.
    security.pki.certificateFiles = [ ./caddy-local-ca.crt ];

    # Pattern A — Caddy's internal CA private key + state. Irreplaceable:
    # if the CA gets regenerated, every device with the current
    # caddy-local-ca.crt installed needs to re-trust the new public
    # cert. Static `caddy` user, real /var/lib/caddy directory.
    nori.backups.caddy.include = [ "/var/lib/caddy" ];
  })
]
