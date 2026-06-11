{
  config,
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
    # Caddy reverse proxy — clean *.<nori.domain> subdomain per service,
    # HTTPS via Let's Encrypt + Cloudflare DNS-01 (no per-device CA
    # install).
    #
    # Domain is owned (phibkro.org); Cloudflare hosts the zone. The
    # existing sops secret `cloudflare_api_token` (apps.yaml) has DNS
    # edit scope on the zone — Caddy uses it to write the TXT records
    # LE wants during the DNS-01 challenge, then removes them. No port
    # 80 ever opened to the internet; the homelab stays LAN/tailnet-only.
    #
    # Cert lifecycle: Caddy auto-renews each per-vhost cert ~30 days
    # before expiry (LE issues 90-day certs). State + private keys at
    # /var/lib/caddy/.local/share/caddy/certificates/; covered by the
    # Pattern A backup below. Rate limits: LE per-domain caps at 50
    # certs/week — we have ~30 vhosts so single rebuild is fine but
    # don't churn the cert config in a loop.
    #
    # DNS path: Blocky's customDNS (modules/services/blocky.nix) maps
    # each *.<nori.domain> to nori.lanIp (workstation today, pi post
    # ADR-0003 pivot). LAN clients hit Caddy directly; off-LAN tailnet
    # clients reach the same address via pi's subnet route advertisement
    # (192.168.1.0/24, needs --accept-routes on the client). Public
    # DNS for *.<nori.domain> has no A records — the homelab is
    # unreachable from the internet.

    services.caddy = {
      enable = true;

      # Caddy with Cloudflare DNS plugin baked in. xcaddy builds a
      # fresh binary embedding the named plugin — hash is the source
      # tree's content-addressed digest; pin both the plugin version
      # and the hash so reproducible rebuilds don't silently float.
      # Update both together when bumping plugin version.
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-bzMqxWTqrJ1skZmRTXyEMCKStXpljbqe5r0Ve2cnBfM=";
      };

      # LE registration email (rotation reminders, expiry warnings).
      email = "philib.krogh@gmail.com";

      # `acme_dns cloudflare` switches every vhost's automatic HTTPS
      # to DNS-01 against the Cloudflare-hosted phibkro.org zone.
      # `{env.CF_API_TOKEN}` is read from the systemd environment via
      # the sops template + EnvironmentFile wired below — the token
      # never lands in /nix/store.
      #
      # `acme_ca` pins Let's Encrypt as the sole issuer. Caddy's default
      # tries ZeroSSL first then falls back to LE; pinning to LE
      # eliminates a redundant API-call burst (and ZeroSSL was failing
      # with HTTP 429 during first-issuance, multiplying rate-limit
      # exposure).
      globalConfig = ''
        acme_dns cloudflare {env.CF_API_TOKEN}
        acme_ca https://acme-v02.api.letsencrypt.org/directory
      '';

      # Virtual hosts are NOT defined here. They're auto-generated from
      # `nori.lanRoutes.<name>` declarations in each service's own
      # module — see modules/effects/lan-route.nix for the option +
      # generator. Adding/renaming a route happens at the source
      # (the service module), not here.
    };

    # Transitional `*.nori.lan` redirect vhost. Family devices still
    # holding bookmarks to the old domain hit Caddy here — Caddy serves
    # an internal-CA cert (the same root that's already installed on
    # those devices from before ADR-0004), then 301s to the same path
    # under `home.phibkro.org`. Devices without the internal CA installed
    # still get the redirect at the HTTP layer; only the TLS handshake
    # itself depends on the old trust chain.
    #
    # Drop this block (and the parallel transitional entries in
    # modules/effects/lan-route.nix § blocky customDNS) once family
    # bookmarks have all migrated. Internal CA still lives at
    # /var/lib/caddy/.local/share/caddy/pki/authorities/local/ so the
    # cert keeps issuing without operator intervention until then.
    services.caddy.virtualHosts."*.nori.lan".extraConfig = ''
      tls internal
      @sub header_regexp Host ^([^.]+)\.nori\.lan$
      redir @sub https://{re.sub.1}.${config.nori.domain}{uri} 301
    '';

    # Dedicated Cloudflare API token for ACME DNS-01. Separate from the
    # operator's existing `cloudflare_api_token` (cfut_-prefix, a
    # wrangler-issued user OAuth token used for app-deploy flows) which
    # Caddy's cloudflare-dns plugin rejects on format. This one is a
    # proper Account API Token (40-char alphanumeric, no prefix) scoped
    # to DNS:Edit on the phibkro.org zone — the minimal grant needed to
    # write/remove `_acme-challenge.*` TXT records.
    sops.secrets.cloudflare-acme-token = {
      sopsFile = ../../secrets/apps.yaml;
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

    # Skip the system trust install attempt — LE roots are already in
    # the system trust store, no install needed. (Variable retained
    # from the previous internal-CA setup; harmless when ACME is in
    # use, removed at the next sweep.)
    systemd.services.caddy.environment.CADDY_AUTO_TRUST = "0";

    nori.harden.caddy = { };

    # Open globally, not per-interface: with `*.<nori.domain>` resolving
    # to nori.lanIp (set in modules/effects/lan-route.nix), requests
    # arrive on the LAN interface for LAN clients and on tailscale0 for
    # off-LAN tailnet clients via pi's subnet route. Same precedent as
    # Blocky's :53. The router doesn't forward :80/:443 inbound from
    # WAN, so the host firewall is just the second layer.
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    # Pattern A — Caddy's ACME account key + per-vhost cert + key state.
    # Losing /var/lib/caddy means LE re-issuance from scratch on next
    # startup. LE per-domain rate limit is 50 certs/week; with ~30
    # vhosts a rebuild stays well under, but a backup means we don't
    # have to think about it.
    nori.backups.caddy.include = [ "/var/lib/caddy" ];
  })
]
