{ config, lib, pkgs, ... }:

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
}
