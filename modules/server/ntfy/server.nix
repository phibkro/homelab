{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ntfy-sh server — internal alert hub for the homelab. Lives on the
  # appliance host (nori-pi) for the same reason beszel-hub does:
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
  # State (auth db, attachments) at /var/lib/private/ntfy-sh on Pi.
  # Tiny (~150K). DynamicUser via the upstream module.

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://alert.nori.lan";
      listen-http = ":8081";
      auth-default-access = "read-write";
      behind-proxy = false;
    };
  };

  systemd.services.ntfy-sh.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  # Tailnet exposure for the cross-host Caddy reverse-proxy backend.
  # Caddy on station hits 100.100.71.3:8081 over tailnet; clients reach
  # it via https://alert.nori.lan (terminated by station's Caddy).
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8081 ];

  # Same anti-write rationale as beszel-hub: Pi's flash storage
  # philosophy + non-load-bearing state (auth db is unused under
  # auth-default-access=read-write; cache.db is ephemeral). Defer until
  # Pi gains the planned local fast-restore disk repo.
  nori.backups.ntfy.skip = "Hub on appliance host (nori-pi). Pi flash anti-write posture; auth db effectively unused (read-write default), cache rebuilds on restart.";
}
