{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  internetRoutes = lib.filterAttrs (_: route: route.reachability == "internet") config.nori.lanRoutes;
  internetDomains = lib.mapAttrsToList (name: _: "${name}.${config.nori.domain}") internetRoutes;
  recordComment = "Managed by homelab nori.lanRoutes reachability=internet";
in
{
  assertions = [
    {
      assertion = internetDomains != [ ];
      message = "cloudflare-ddns is enabled, but nori.lanRoutes has no internet-reachable routes";
    }
  ];

  /*
    The public DNS inventory is deliberately derived from the same
    exact-host allowlist Caddy consumes. No wildcard, no operator route,
    and no second handwritten list that can drift open.

    Records stay DNS-only: sustained Jellyfin/Navidrome media delivery
    must go directly to the residential connection rather than through
    Cloudflare's self-serve proxy or Tunnel. IPv6 is disabled until the
    router's IPv6 ingress policy is explicitly designed and tested.
  */
  services.cloudflare-ddns = {
    enable = true;
    credentialsFile = config.sops.templates."cloudflare-ddns-env".path;
    domains = [ ];
    ip4Domains = internetDomains;
    ip6Domains = [ ];
    provider = {
      ipv4 = "cloudflare.trace";
      ipv6 = "none";
    };
    updateCron = "@every 5m";
    updateOnStart = true;
    # On a declarative route removal, systemd stops the old unit before
    # starting the new one. Delete the old unit's owned records then so an
    # internet -> internal transition cannot leave stale public DNS.
    deleteOnStop = true;
    ttl = 1;
    proxied = "false";
    inherit recordComment;
  };

  sops.secrets.cloudflare-ddns-token = {
    sopsFile = inputs.self + "/secrets/apps.yaml";
    key = "cloudflare_api_token";
  };

  sops.templates."cloudflare-ddns-env" = {
    owner = "cloudflare-ddns";
    group = "cloudflare-ddns";
    mode = "0400";
    content = ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare-ddns-token}
    '';
  };

  /*
    The first cutover used a persistent systemd-control bridge to avoid
    coupling this service to an unrelated Pi kernel upgrade. The first
    successful declarative activation owns the unit and sops credential
    again, so remove only those exact bridge artifacts before systemd
    reloads the generated unit.
  */
  system.activationScripts.cloudflare-ddns-runtime-bridge-cleanup.text = ''
    ${pkgs.coreutils}/bin/rm -f \
      /etc/systemd/system.control/cloudflare-ddns.service \
      /etc/systemd/system.control/multi-user.target.d/zz-cloudflare-ddns.conf \
      /run/systemd/system/cloudflare-ddns.service \
      /run/systemd/system/multi-user.target.wants/cloudflare-ddns.service \
      /run/cloudflare-ddns.env \
      /var/lib/cloudflare-ddns/credentials.env
  '';

  # The upstream unit combines ProtectSystem=strict with a writable cache
  # directory. Make that one state path explicit; everything else remains
  # read-only under the service's existing systemd sandbox.
  systemd.services.cloudflare-ddns.serviceConfig = {
    ReadWritePaths = [ "/var/lib/cloudflare-ddns" ];
    # Favonia's ownership selector is newer than the pinned NixOS module's
    # option surface. Anchor it to our write-side comment so cleanup can
    # never mutate a manually or independently managed record.
    Environment = [
      "MANAGED_RECORDS_COMMENT_REGEX=^Managed by homelab nori\\.lanRoutes reachability=internet$"
    ];
  };

  nori.harden.cloudflare-ddns = { };

  nori.backups.cloudflare-ddns.skip = "stateless — desired records derive from internet lanRoutes; the API token is sops-managed";
}
