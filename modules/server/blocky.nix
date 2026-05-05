{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.blocky;
in
{
  # Blocky: ad-blocking DNS resolver, LAN-facing.
  #
  # Two roles per `nori.blocky.role`:
  #   * self-hosted: full resolver + auto-generated *.nori.lan map
  #     from nori.lanRoutes (the workstation case). Customers query
  #     this Blocky for everything: ads filtered, *.nori.lan resolved
  #     locally, everything else upstreamed.
  #   * forwarder:   ads filtered + non-nori.lan resolved upstream;
  #     *.nori.lan queries conditionally forwarded to workstation's
  #     Blocky (pi case). Pi doesn't need to know what services
  #     exist on station; it just delegates the suffix.
  #
  # Tailscale DNS push order (set in admin console): primary = whichever
  # role-self-hosted-or-forwarder host you trust to be up most. With Pi
  # running, Pi becomes primary (appliance, lower failure surface);
  # station's Blocky is secondary fallback.
  #
  # Listens on 0.0.0.0:53. Upstreams to Cloudflare + Quad9 with
  # parallel_best (whichever responds first wins).
  #
  # The host itself keeps using Tailscale MagicDNS (100.100.100.100)
  # for its own queries — Blocky serves downstream clients, not the
  # host. This avoids losing tailnet hostname resolution.

  options.nori.blocky.role = lib.mkOption {
    type = lib.types.enum [
      "self-hosted"
      "forwarder"
    ];
    default = "self-hosted";
    description = ''
      How this host's Blocky resolves *.nori.lan.

      * `self-hosted` — auto-generates the *.nori.lan customDNS map
        from `nori.lanRoutes` declarations. Use on hosts that import
        the service modules (i.e. the host the services run on).
      * `forwarder` — conditionally forwards *.nori.lan queries to
        the host that runs the services (nori.lanIp). Use on
        observability-only hosts (pi) so they don't have to
        know what services exist on the server.
    '';
  };

  options.nori.blocky.forwardTarget = lib.mkOption {
    type = lib.types.str;
    default = config.nori.lanIp;
    description = ''
      For `forwarder` role: where to send *.nori.lan queries.
      Defaults to `nori.lanIp` (the canonical service host).
    '';
  };

  config.services.blocky = {
    enable = true;
    settings = {
      ports.dns = 53;

      # bootstrapDns is used only for resolving Blocky's *own* outgoing
      # URLs — the upstream resolvers below, blocklist sources, etc.
      # — independent of /etc/resolv.conf. Required here because the
      # Tailscale DNS push points the host's resolver back at this very
      # Blocky instance (the workhorse tailnet IP set as global tailnet
      # nameserver), which would otherwise create a chicken-and-egg
      # loop on startup — Blocky can't resolve raw.githubusercontent.com
      # to download the blocklist before it's serving DNS.
      bootstrapDns = [
        { upstream = "1.1.1.1"; }
        { upstream = "9.9.9.9"; }
      ];

      upstreams = {
        strategy = "parallel_best";
        groups.default = [
          "1.1.1.1"
          "9.9.9.9"
          "1.0.0.1"
        ];
      };

      blocking = {
        denylists.ads = [
          "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        ];
        clientGroupsBlock.default = [ "ads" ];
        loading.refreshPeriod = "24h";
      };

      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };

      # customDNS.mapping for self-hosted role is auto-generated from
      # nori.lanRoutes declarations in each service module — see
      # modules/effects/lan-route.nix. Only customTTL stays here as the
      # global default for those entries. On forwarder hosts the map
      # stays empty; conditional.mapping does the work instead.
      customDNS.customTTL = "1h";

      # Conditional forwarding: applies to the `forwarder` role.
      # *.nori.lan queries get sent to the canonical service host's
      # Blocky (which has the actual map). Other queries flow through
      # the upstream resolver chain unaffected.
      conditional.mapping = lib.mkIf (cfg.role == "forwarder") {
        "nori.lan" = cfg.forwardTarget;
      };

      log = {
        level = "info";
        format = "text";
      };
    };
  };

  # DNS serves all LAN clients — open globally, not per-interface.
  # Safe because nothing forwards :53 inbound from outside the LAN
  # at the router level; the host firewall is just the second layer.
  config.networking.firewall.allowedTCPPorts = [ 53 ];
  config.networking.firewall.allowedUDPPorts = [ 53 ];

  # Default-deny filesystem access — Blocky only needs its config
  # (in /nix/store via the module) and network. No host paths.
  config.nori.harden.blocky = { };

  # Stateless — Blocky's runtime state is just the in-memory cache
  # of upstream-resolved A/AAAA records and the downloaded blocklists,
  # both of which rebuild from declarative Nix config + bootstrapDns
  # on every restart. DynamicUser too (path /var/lib/private/blocky).
  config.nori.backups.blocky.skip =
    "Stateless — config in Nix; cache + blocklists rebuild on restart.";
}
