{ config, lib, pkgs, ... }:

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
  #   Blocky's customDNS (modules/services/blocky.nix) maps each
  #   *.nori.lan name to nori-station's tailnet IP (100.81.5.122).
  #   Tailnet clients hit that IP, traffic flows over the tailnet,
  #   reaches Caddy on :443, virtual-host routing fans out to backends.
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

    virtualHosts = {
      "auth.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:9091
        '';
      };
      "jellyfin.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:8096
        '';
      };
      "chat.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
      "ai.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:11434
        '';
      };
      "gatus.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:8082
        '';
      };
      "beszel.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:8090
        '';
      };
      "alert.nori.lan" = {
        extraConfig = ''
          reverse_proxy localhost:8081
        '';
      };
    };
  };

  systemd.services.caddy = {
    # Skip the system trust install attempt; the hardened service
    # can't write to /etc/ssl/... and there's no point anyway since
    # we install the root cert per-device manually.
    environment.CADDY_AUTO_TRUST = "0";

    serviceConfig = {
      ProtectHome = lib.mkForce true;
      TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
      BindReadOnlyPaths = [ ];
    };
  };

  # Caddy listens on 443 (HTTPS); 80 too if we want plaintext-redirect.
  # Tailnet only — backend services keep their individual tailnet
  # ports open as well so old URLs keep working during transition;
  # close them per-service later if you want to enforce going through
  # Caddy.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 80 443 ];
}
