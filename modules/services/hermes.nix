_:

# Hermes Agent dashboard — Caddy lanRoute on the workstation.
#
# Split from ./default.nix because that module is home-manager scope
# (user package + user systemd service) and `nori.lanRoutes` is a NixOS
# option. Both live under home/hermes/ for ownership clarity;
# pc.nix imports ./default.nix (HM) and workstation/default.nix
# imports ./route.nix (NixOS).
#
# Naming: brand-identified `hermes.nori.lan` rather than function-named
# `agent.nori.lan` — the convention exception applies here (the brand
# IS the identity: Hermes is the specific persistent-memory agent on
# this host, not a generic interchangeable "agent" slot).
#
# Audience operator: tailnet membership is the auth perimeter, and
# Hermes' dashboard exposes API keys + chat history + memory — never
# something a family-tier user should reach. No Authelia layer on top
# because operator-tier devices are already authenticated by Tailscale
# (the qBittorrent/Grafana/Stremio precedent).

{
  nori.lanRoutes.hermes = {
    port = 9119;
    runsOn = "workstation";
    exposeOnTailnet = true; # pi's Caddy proxies cross-host over tailnet
    audience = "operator";
    # Hermes' dashboard binds to 127.0.0.1 and rejects any Host header
    # that isn't a loopback name as a DNS-rebinding defence
    # (GHSA-ppp5-vxwm-4cf7). Rewrite Host before forwarding so the
    # public name `hermes.nori.lan` reaches a backend that thinks it's
    # being asked for `127.0.0.1:9119`. The same defence is applied at
    # the WebSocket-upgrade handler against `Origin` — required for
    # the embedded chat PTY to work over the proxied route, otherwise
    # chat sessions refuse with `origin_mismatch …`.
    upstreamHostHeader = "127.0.0.1:9119";
    upstreamOriginHeader = "http://127.0.0.1:9119";
    monitor = { };
    dashboard = {
      title = "Hermes";
      icon = "si:nousresearch";
      group = "Admin";
      description = "Persistent-memory coding agent — sessions, memory, skills, config.";
    };
  };
}
