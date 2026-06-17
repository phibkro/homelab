{ config, lib, ... }:

lib.mkMerge [
  {
    nori.services.ntfy-server.tags = [
      "network-appliance"
      "alerting"
      "stateful"
    ];
  }
  (lib.mkIf config.nori.services.ntfy-server.enabled {
    /**
      ntfy-sh server — internal alert hub for the homelab. Lives on the
      appliance host (pi) for the same reason beszel-hub does:
      alert/observability infra shouldn't share fate with the host being
      alerted. Migrated from station 2026-04-29.

      Today's actual alert path still goes to ntfy.sh (public) — both
      Gatus and the notify@ template POST there directly because the
      operator's mobile app subscription is on ntfy.sh. The local instance
      is pre-positioned for future internal-only alerts (services that
      shouldn't traverse public internet).

      Auth posture (hardened 2026-06-15 per docs/runbooks/ntfy-auth-
      bootstrap.md): `auth-default-access = "deny"` — no anonymous
      publish/subscribe. Threat model is agentic workloads on tailnet
      (e.g. pavilion) spoofing alerts; locking publish closes that
      surface even before anything starts using the local hub.
      `/v1/health` stays unauthenticated by upstream design, so Gatus's
      monitor probe on the alert.${nori.domain} route keeps working.

      Publisher provisioning is currently MANUAL one-time:
        sudo NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db \
          ntfy user add --role=admin publisher
        # → prompts for password; paste the value from sops at key
        #   `ntfy-publisher-token` (operator generated 2026-06-14).
      Declarative bootstrap deferred until the CLI's non-interactive
      password shape is verified — runbook's example doesn't match
      upstream's documented syntax. Tracked as a small follow-up.
    */
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://alert.${config.nori.domain}";
        listen-http = ":8081";
        auth-default-access = "deny";
        auth-file = "/var/lib/ntfy-sh/user.db";
        behind-proxy = false;
      };
    };

    /*
      Token lives in sops so a future declarative bootstrap can read it
      without operator intervention. Mode 0440 (root + ntfy group); ntfy-
      sh.service is DynamicUser=true so file access happens via group
      membership rather than uid match.
    */
    sops.secrets.ntfy-publisher-token = {
      mode = "0440";
    };

    nori.harden.ntfy-sh = { };

    /*
      https://alert.${nori.domain} vhost is declared in ./notify.nix on
      hosts with Caddy. Open the backend port on the tailnet so Caddy
      can reach it.
    */
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8081 ];

    nori.backups.ntfy.skip = "Hub on appliance host (pi). Pi flash anti-write posture; auth db tiny (one publisher row), recreated from sops + manual ntfy user add if lost.";
  })
]
