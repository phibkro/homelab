_:

{
  # ntfy-sh server — internal alert hub for the homelab. Lives on the
  # appliance host (pi) for the same reason beszel-hub does:
  # alert/observability infra shouldn't share fate with the host being
  # alerted. Migrated from station 2026-04-29.
  #
  # Today's actual alert path goes to ntfy.sh (public) — both Gatus and
  # the notify@ template POST there directly because the user's mobile
  # app subscription is on ntfy.sh. The local instance is pre-positioned
  # for future internal-only alerts (services that shouldn't traverse
  # public internet) — same role it played on station, just relocated
  # to the side of the house that survives station outages.
  #
  # Single-user tailnet → no auth (auth-default-access=read-write; any
  # tailnet host can publish/subscribe). Multi-user later: flip to
  # "deny" + per-topic publish tokens in sops + Authorization headers.
  #
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://alert.nori.lan";
      listen-http = ":8081";
      auth-default-access = "read-write";
      behind-proxy = false;
    };
  };

  nori.harden.ntfy-sh = { };

  # https://alert.nori.lan vhost is declared in ./notify.nix on hosts
  # with Caddy. Open the backend port on the tailnet so they can reach it.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8081 ];

  nori.backups.ntfy.skip = "Hub on appliance host (pi). Pi flash anti-write posture; auth db effectively unused (read-write default), cache rebuilds on restart.";
}
