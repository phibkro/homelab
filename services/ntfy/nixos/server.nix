{ config, ... }:

let
  alert = config.nori.inventory.routes.alert;
in

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
    wired on workstation — infra/workstation/default.nix) is
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

    Publisher provisioning is a manual one-time operation:
      sudo NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db \
        ntfy user add --role=admin publisher
      # → prompts for password; paste the value from sops at key
      #   `ntfy-publisher-token` (operator generated 2026-06-14).

    deny also blocks anonymous SUBSCRIBE. Unlike public ntfy.sh, where an
    obscure topic name gates read access, the phone app must authenticate to
    subscribe to the local agents topic. The current account is the publisher
    user. No declarative users API is configured.
  */
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://${alert.hostname}";
      listen-http = ":${toString alert.port}";
      auth-default-access = "deny";
      auth-file = "/var/lib/ntfy-sh/user.db";
      behind-proxy = false;
    };
  };

  /*
    The SOPS token is the source for manual publisher enrollment. Mode 0440
    grants access to root and the ntfy group. ntfy-sh.service is DynamicUser,
    so file access uses group membership instead of a stable uid.
  */
  sops.secrets.ntfy-publisher-token = {
    mode = "0440";
  };

  nori.harden.ntfy-sh = { };

  nori.backups.ntfy.skip = "Hub on appliance host (pi). Pi flash anti-write posture; auth db tiny (one publisher row), recreated from sops + manual ntfy user add if lost.";
}
