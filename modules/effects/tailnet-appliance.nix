{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    filterAttrs
    attrValues
    concatMapStringsSep
    ;

  # Appliances whose DNS + egress are intercepted by *this* host.
  # Filtered the same shape as lan-route's runsOn-filter so the effect
  # imports cleanly across the fleet without per-host gating.
  localAppliances = filterAttrs (
    _: a: a.interceptedAt == config.networking.hostName
  ) config.nori.tailnet.appliances;

  # Pi's own tailnet IP — DNAT target for the :53 redirect. Local IP
  # required (PREROUTING DNAT can't target 127.0.0.1 for routed traffic);
  # read from the registry so it stays correct if the host's tailnet IP
  # ever moves.
  selfTailnetIp = config.nori.hosts.${config.networking.hostName}.tailnetIp;

  # Public DNS/DoH endpoint IPs that hardcoded-resolver appliances are
  # known to fall back to. Source: pi-hole/AdGuard community DoH blocklists
  # (jpgpi250/piholemanual, nextdns.io/blocklist/doh). IPs not domains —
  # the appliance's DoH client doesn't consult our DNS; it talks straight
  # to these. New entries land here when a future appliance proves to use
  # another resolver.
  knownPublicResolvers = [
    "8.8.8.8" # dns.google
    "8.8.4.4" # dns.google
    "1.1.1.1" # cloudflare-dns.com
    "1.0.0.1" # cloudflare-dns.com
    "9.9.9.9" # quad9.net
    "149.112.112.112" # quad9.net
    "208.67.222.222" # OpenDNS
    "208.67.220.220" # OpenDNS
    "94.140.14.14" # AdGuard
    "94.140.15.15" # AdGuard
  ];
in
{
  # ── Architectural note ────────────────────────────────────────────
  # The correct layer for "force my LAN's DNS through Blocky" is the
  # network egress gateway — a real router (OPNsense/OpenWRT) in front
  # of a bridge-mode modem. This effect does the same enforcement at the
  # WRONG layer (pi-as-tailnet-exit) because the ISP-supplied Genexis
  # doesn't go into bridge mode and a real router isn't on the budget.
  #
  # The compromise's limits (named, not hidden):
  #   * Only catches devices that route through this host. If an
  #     appliance drops its exit-node selection, interception silently
  #     stops and ads return. No alert today.
  #   * Future appliances using DoH-over-:443 to a resolver NOT in
  #     knownPublicResolvers above bypass the filter — extend the list
  #     as new resolvers are observed.
  #   * Fate-shares ad-blocking with tailnet membership. LAN-only devices
  #     that hardcode DNS get no protection.
  #   * **YouTube on chromecast: not solvable by DNS.** YouTube uses
  #     server-side ad insertion (SSAI) — ads stream from the same
  #     `*.googlevideo.com` hosts as the video content; blocking that
  #     domain breaks YouTube, allowing it lets ads through. There's
  #     no DNS-layer wedge. Verified 2026-06-15: chromecast queries
  #     reach Blocky (73 in 10min, 8 blocked: tpc.googlesyndication.com
  #     etc.), but YouTube ads still play. Conventional ads ARE blocked
  #     for everything except cast-app YouTube. Real fixes are
  #     non-DNS: YouTube Premium, SmartTubeNext on the chromecast,
  #     or casting from NewPipe on a phone.
  #
  # Tracked in docs/reference/recovery.md § "Reactive triggers" → "real router".
  # When that lands, this effect goes away; the same registry can drive
  # the router's nftables config via a different generator.

  options.nori.tailnet.appliances = mkOption {
    default = { };
    description = ''
      Registry of tailnet-joined appliances whose outbound DNS and known-
      DoH-endpoint egress are transparently intercepted on the host named
      by `interceptedAt`. Each appliance is presumed to hardcode a public
      resolver (chromecast/Google TV hardcode 8.8.8.8) and ignore both
      DHCP and Tailscale's DNS push — system-level DNS config can't reach
      them, so we enforce policy at the network path instead.

      An entry MUST correspond to a device tagged `tag:appliance` in the
      Tailscale ACL — the tag and the registry encode the same trust
      boundary at different layers (ACL = who-can-reach-what; this =
      whose-egress-we-rewrite). Drift between the two is a latent bug.
    '';
    example = lib.literalExpression ''
      {
        chromecast = {
          tailnetIp     = "100.94.135.114";
          interceptedAt = "pi";
        };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          tailnetIp = mkOption {
            type = types.str;
            description = ''
              Tailnet IP of the appliance. Stable per-device; if the
              appliance ever rejoins the tailnet it gets a new IP and
              this needs updating (the registry is the canary).
            '';
          };
          interceptedAt = mkOption {
            type = types.str;
            example = "pi";
            description = ''
              Host on which the appliance's traffic is intercepted —
              must be in the appliance's network path (its tailnet exit
              node, its subnet router, or the LAN gateway). Today only
              pi qualifies; a future LAN-gateway-pi would too.
            '';
          };
        };
      }
    );
  };

  config = mkIf (localAppliances != { }) {
    # Switches the NixOS firewall module from iptables to nftables backend
    # so our custom tables coexist in one ruleset. `networking.firewall.*`
    # options keep working transparently.
    networking.nftables.enable = true;

    networking.nftables.tables.tailnet-appliance = {
      family = "ip";
      content = ''
        # PREROUTING DNAT: rewrite outbound :53 from each appliance to
        # this host's Blocky (which binds *:53). Appliance keeps thinking
        # it's talking to its hardcoded public resolver; we silently
        # answer with Blocky's adblocked view.
        chain dns-intercept {
          type nat hook prerouting priority dstnat; policy accept;
        ${concatMapStringsSep "\n" (
          a:
          "ip saddr ${a.tailnetIp} udp dport 53 dnat to ${selfTailnetIp}:53"
          + "\n"
          + "ip saddr ${a.tailnetIp} tcp dport 53 dnat to ${selfTailnetIp}:53"
        ) (attrValues localAppliances)}
        }

        # FORWARD drop: block appliance traffic to known public-resolver
        # IPs on :443 (DoH). If the appliance falls back to encrypted
        # DNS when :53 is intercepted, we want it to fail rather than
        # silently bypass Blocky.
        chain doh-egress-drop {
          type filter hook forward priority filter; policy accept;
        ${concatMapStringsSep "\n" (
          a:
          concatMapStringsSep "\n" (
            ep: "        ip saddr ${a.tailnetIp} ip daddr ${ep} tcp dport 443 drop"
          ) knownPublicResolvers
        ) (attrValues localAppliances)}
        }
      '';
    };
  };
}
