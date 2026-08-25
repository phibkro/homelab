{ config, ... }:

{
  /**
    ntfy-sh server — internal alert hub for the homelab. Lives on the
    appliance host (pi) for the same reason beszel-hub does:
    alert/observability infra shouldn't share fate with the host being
    alerted. Migrated from station 2026-04-29.

    Gatus and the notify@ template still POST straight to ntfy.sh
    (public), by design — those are CRITICAL INFRA alerts and need to
    survive the homelab itself being down, so routing them through a
    service the homelab hosts would be self-defeating.

    2026-07-23: the FLEET/AGENT channel (nori.alerts.channels.agents,
    wired on workstation — modules/machines/workstation/default.nix) is
    now the first real publisher against THIS local instance instead of
    ntfy.sh. Volume from a running agent fleet (every turn-end/
    permission/question ping) was tripping ntfy.sh's public rate limit
    (429s) and sharing that quota with alerts that most need to get
    through; agent chatter carries no uptime-independence requirement,
    so it's the one channel that can safely live here.

    Auth posture (hardened 2026-06-15 per docs/runbooks/ntfy-auth-
    bootstrap.md): `auth-default-access = "deny"` — no anonymous
    publish/subscribe. Threat model is agentic workloads on tailnet
    (for example, agent hosts) spoofing alerts; locking publish closes that
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

    deny also blocks anonymous SUBSCRIBE — unlike ntfy.sh, where a
    topic's obscure name alone gates read access, the phone app can't
    just subscribe to the agents topic here without credentials. Until
    a scoped grant is added (`ntfy access '*' <agents-topic> read-only`,
    run once on pi — same "no declarative users API yet" constraint as
    the publisher above), the operator's app has to log into this
    server AS the publisher user to read the agents topic. Tracked
    alongside the publisher bootstrap follow-up.
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
    The alert endpoint is declared by manifests/server.nix. Open the
    backend port on the tailnet so Caddy can reach it.
  */
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8081 ];

  nori.backups.ntfy.skip = "Hub on appliance host (pi). Pi flash anti-write posture; auth db tiny (one publisher row), recreated from sops + manual ntfy user add if lost.";
}
