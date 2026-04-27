{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Blocky: ad-blocking DNS resolver, LAN-facing.
  #
  # Per DESIGN.md L168-174, the long-term plan is two adblock-aware
  # resolvers (nori-pi primary + nori-station secondary) so a single
  # outage doesn't break LAN DNS. nori-pi is deferred (no NixOS-bootable
  # USB SSD), so this instance acts as the only LAN DNS for now.
  #
  # Listens on 0.0.0.0:53 so all LAN clients via router DHCP can use
  # it. Upstreams to Cloudflare + Quad9 with parallel_best strategy
  # (whichever responds first wins).
  #
  # The host itself keeps using Tailscale MagicDNS (100.100.100.100)
  # for its own queries — Blocky serves downstream LAN clients, not
  # the host. This avoids losing tailnet hostname resolution.
  #
  # Activation order:
  #   1. nixos-rebuild switch (lands Blocky on the host, port 53 open)
  #   2. Test: `dig @192.168.1.181 example.com` (positive),
  #            `dig @192.168.1.181 doubleclick.net` (returns 0.0.0.0)
  #   3. Router admin UI: change DHCP DNS server to 192.168.1.181
  #   4. Reconnect a client device, verify ads blocked

  services.blocky = {
    enable = true;
    settings = {
      ports.dns = 53;

      # bootstrapDns is used only for resolving Blocky's *own* outgoing
      # URLs — the upstream resolvers below, blocklist sources, etc.
      # — independent of /etc/resolv.conf. Required here because the
      # Tailscale DNS push points the host's resolver back at this very
      # Blocky instance (100.81.5.122 set as global tailnet nameserver),
      # which would otherwise create a chicken-and-egg loop on startup
      # — Blocky can't resolve raw.githubusercontent.com to download
      # the blocklist before it's serving DNS.
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

      # customDNS.mapping is auto-generated from nori.lanRoutes
      # declarations in each service module — see
      # modules/lib/lan-route.nix. Only customTTL stays here as the
      # global default for those entries.
      customDNS.customTTL = "1h";

      log = {
        level = "info";
        format = "text";
      };
    };
  };

  # DNS serves all LAN clients — open globally, not per-interface.
  # Safe because nothing forwards :53 inbound from outside the LAN
  # at the router level; the host firewall is just the second layer.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  # Default-deny filesystem access — Blocky only needs its config
  # (in /nix/store via the module) and network. No host paths.
  systemd.services.blocky.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  # Stateless — Blocky's runtime state is just the in-memory cache
  # of upstream-resolved A/AAAA records and the downloaded blocklists,
  # both of which rebuild from declarative Nix config + bootstrapDns
  # on every restart. DynamicUser too (path /var/lib/private/blocky).
  nori.backups.blocky.skip = "Stateless — config in Nix; cache + blocklists rebuild on restart.";
}
