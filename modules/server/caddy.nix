{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Caddy reverse proxy — gives every service a clean subdomain name
  # under *.nori.lan, terminates HTTPS via Caddy's internal CA.
  #
  # The internal CA is auto-generated on first run at
  #   /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
  # Install that root cert on each device once (one-time per device):
  #
  #   # Mac — copy to your machine, then:
  #   sudo security add-trusted-cert -d -r trustRoot \
  #     -k /Library/Keychains/System.keychain root.crt
  #
  #   # iOS — AirDrop the cert, install via Settings → Profile,
  #   # then Settings → General → About → Certificate Trust Settings →
  #   # toggle on for "Caddy Local Authority"
  #
  # After that, every *.nori.lan service works without browser warnings.
  #
  # DNS resolution:
  #   Blocky's customDNS (modules/server/blocky.nix) maps each
  #   *.nori.lan name to nori-station's LAN IP (192.168.1.181). LAN
  #   clients hit Caddy directly with no tailnet hop. Off-LAN tailnet
  #   clients reach the same address via Pi's subnet route
  #   advertisement (192.168.1.0/24); requires --accept-routes on
  #   the client side.
  #
  # Adding a new service later: append a vhost below + a Blocky
  # customDNS entry. That's it.

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

  # Caddy listens on 80 (plaintext-redirect) + 443 (HTTPS). Open
  # globally, not per-interface: with `*.nori.lan` resolving to the
  # workhorse LAN IP (see modules/effects/lan-route.nix nori.lanIp),
  # request traffic arrives on the LAN interface for LAN clients
  # and on tailscale0 for off-LAN tailnet clients via Pi's subnet
  # route. Same precedent as Blocky's :53 (modules/server/blocky.nix);
  # the router doesn't forward :80/:443 inbound from WAN, so the host
  # firewall is just the second layer.
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
  nori.backups.caddy.paths = [ "/var/lib/caddy" ];
}
