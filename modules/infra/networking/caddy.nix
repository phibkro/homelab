{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

lib.mkMerge [
  {
    nori.services.caddy.tags = [
      "network-appliance"
      "stateful"
    ];
  }
  (lib.mkIf config.nori.services.caddy.enabled {
    /**
      Caddy reverse proxy — clean *.<nori.domain> subdomain per service,
      HTTPS via Let's Encrypt + Cloudflare DNS-01 (no per-device CA
      install).

      Domain is owned (phibkro.org); Cloudflare hosts the zone. The
      existing sops secret `cloudflare_api_token` (apps.yaml) has DNS
      edit scope on the zone — Caddy uses it to write the TXT records
      LE wants during the DNS-01 challenge, then removes them. No port
      80 ever opened to the internet; the homelab stays LAN/tailnet-only.

      Cert lifecycle: Caddy auto-renews each per-vhost cert ~30 days
      before expiry (LE issues 90-day certs). State + private keys at
      /var/lib/caddy/.local/share/caddy/certificates/; covered by the
      Pattern A backup below. Rate limits: LE per-domain caps at 50
      certs/week — we have ~30 vhosts so single rebuild is fine but
      don't churn the cert config in a loop.

      DNS path: Blocky's customDNS (modules/infra/networking/blocky.nix) maps
      each *.<nori.domain> to nori.lanIp (workstation today, pi post
      ADR-0003 pivot). LAN clients hit Caddy directly; off-LAN tailnet
      clients reach the same address via pi's subnet route advertisement
      (192.168.1.0/24, needs --accept-routes on the client). Public
      DNS for *.<nori.domain> has no A records — the homelab is
      unreachable from the internet.
    */

    services.caddy = {
      enable = true;

      /*
        Caddy with Cloudflare DNS plugin baked in. xcaddy builds a
        fresh binary embedding the named plugin — hash is the source
        tree's content-addressed digest; pin both the plugin version
        and the hash so reproducible rebuilds don't silently float.
        Update both together when bumping plugin version.
      */
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-8yZDrejNKsaUnUaTUFYbarWNmxafqp2z2rWo+XRsxV8=";
      };

      # LE registration email (rotation reminders, expiry warnings).
      email = "philib.krogh@gmail.com";

      /*
        `acme_dns cloudflare` switches every vhost's automatic HTTPS
        to DNS-01 against the Cloudflare-hosted phibkro.org zone.
        `{env.CF_API_TOKEN}` is read from the systemd environment via
        the sops template + EnvironmentFile wired below — the token
        never lands in /nix/store.

        `acme_ca` pins Let's Encrypt as the sole issuer. Caddy's default
        tries ZeroSSL first then falls back to LE; pinning to LE
        eliminates a redundant API-call burst (and ZeroSSL was failing
        with HTTP 429 during first-issuance, multiplying rate-limit
        exposure).
      */
      globalConfig = ''
        acme_dns cloudflare {env.CF_API_TOKEN}
        acme_ca https://acme-v02.api.letsencrypt.org/directory
      '';

      /**
        Virtual hosts are NOT defined here. They're auto-generated from
        `nori.lanRoutes.<name>` declarations in each service's own
        module — see modules/infra/networking/default.nix for the option +
        generator. Adding/renaming a route happens at the source
        (the service module), not here.
      */
    };

    /*
      `*.nori.lan` 301-redirects to the same path under `nori.domain`,
      HTTP-only. Previously served `tls internal` (Caddy's local CA),
      but browsers reject the unknown CA and refuse to follow the 301
      — caught 2026-06-15 when auth.nori.lan typed in a browser showed
      "your connection is not private" instead of redirecting cleanly.
      HTTP-layer redirects from non-TLS sites are accepted by browsers
      without cert prompts, which is the standard deprecation path.
      https://*.nori.lan typing now gets a clean connection error
      (no TLS handshake offered) — forces bookmark updates rather than
      scary cert warnings.
    */
    services.caddy.virtualHosts."http://*.nori.lan".extraConfig = ''
      @sub header_regexp Host ^([^.]+)\.nori\.lan$
      redir @sub https://{re.sub.1}.${config.nori.domain}{uri} 301
    '';

    /*
      Cloudflare Account API Token (40-char alphanumeric, no prefix),
      scoped DNS:Edit on the phibkro.org zone — the minimal grant
      Caddy's cloudflare-dns plugin needs to write/remove
      `_acme-challenge.*` TXT records for ACME DNS-01.
    */
    sops.secrets.cloudflare-acme-token = {
      sopsFile = inputs.self + "/secrets/apps.yaml";
      key = "cloudflare_acme_token";
      owner = "caddy";
      mode = "0400";
    };

    # sops template mounts as an env file Caddy can source. The
    # placeholder reference is substituted at activation time.
    sops.templates."caddy-acme-env" = {
      owner = "caddy";
      mode = "0400";
      content = ''
        CF_API_TOKEN=${config.sops.placeholder.cloudflare-acme-token}
      '';
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile = config.sops.templates."caddy-acme-env".path;

    nori.harden.caddy = { };

    /*
      Open globally, not per-interface: with `*.<nori.domain>` resolving
      to nori.lanIp (set in modules/infra/networking/default.nix), requests
      arrive on the LAN interface for LAN clients and on tailscale0 for
      off-LAN tailnet clients via pi's subnet route. Same precedent as
      Blocky's :53. The router doesn't forward :80/:443 inbound from
      WAN, so the host firewall is just the second layer.
    */
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    /*
      Pattern A — Caddy's ACME account key + per-vhost cert + key state.
      Losing /var/lib/caddy means LE re-issuance from scratch on next
      startup. LE per-domain rate limit is 50 certs/week; with ~30
      vhosts a rebuild stays well under, but a backup means we don't
      have to think about it.
    */
    nori.backups.caddy.include = [ "/var/lib/caddy" ];
  })
]
