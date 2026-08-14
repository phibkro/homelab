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
    (e.g. pavilion) spoofing alerts; locking publish closes that
    surface even before anything starts using the local hub.
    `/v1/health` stays unauthenticated by upstream design, so Gatus's
    monitor probe on the alert.${nori.domain} route keeps working.

    Publisher provisioning is DECLARATIVE (2026-07-24), via ntfy's own
    config-file provisioning (auth-users / auth-tokens / auth-access,
    upstream ≥2.11). ntfy reconciles user.db to match these on every
    start: it creates/updates the declared entries and deletes ones it
    previously provisioned but no longer sees — so drift is
    unrepresentable, not something a bootstrap script has to detect.
    The prior MANUAL steps (`ntfy user add`, `ntfy access`) are
    superseded; the CLI also can't pin a SPECIFIC access-token value
    (`ntfy token add` only mints random ones), which the workstation
    publisher's fixed Bearer token requires — only config provisioning
    can reproduce it.

    The three values are secrets, so they never enter the store: a
    sops template renders the NTFY_AUTH_* env vars at activation and
    ntfy reads them via EnvironmentFile (same shape as caddy's ACM env,
    modules/infra/networking/caddy/runtime.nix). What each carries:
      - auth-users:  publisher (role admin) + a bcrypt password hash
                     (ntfy-publisher-password-hash). The password is an
                     unused artifact — publishers authenticate with the
                     token below, never basic auth — but a token's user
                     must be a provisioned user, so the hash is required.
      - auth-tokens: the exact tk_ access token the workstation sends as
                     `Authorization: Bearer <ntfy-publisher-token>`
                     (alerts.nix), so a pi reflash reproduces the CURRENT
                     working credential, not a new incompatible one.
      - auth-access: `everyone:<agents-topic>:ro`, topic read from the
                     sops secret at render time (never in the store) —
                     the scoped anonymous READ that lets the operator's
                     phone app subscribe to the agents topic without
                     logging in, while deny still blocks anonymous
                     publish (spoof surface stays closed).
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
    Provisioning inputs. All three are consumed only through the sops
    template below (rendered as root, read by systemd before ntfy's
    DynamicUser drop) — ntfy never reads these files directly, so their
    standalone mode is the restrictive default.

      ntfy-publisher-token         the tk_ Bearer credential (shared with
                                   workstation's agent-notify publisher)
      ntfy-agents-channel          the agents topic name (also declared on
                                   workstation, where the publisher lives)
      ntfy-publisher-password-hash bcrypt hash of the publisher's (unused)
                                   password; auth-users requires a hash
  */
  sops.secrets.ntfy-publisher-token = { };
  sops.secrets.ntfy-agents-channel = { };
  sops.secrets.ntfy-publisher-password-hash = { };

  /*
    Renders NTFY_AUTH_* env vars from the sops placeholders at activation
    (values substituted then, so they land in /run, not the store). ntfy
    reconciles user.db against these on start — idempotent by construction
    against the already-provisioned live db (same publisher user, same
    token, same grant → an update, never a duplicate). restartUnits
    re-provisions on a sops edit + rebuild.
  */
  sops.templates."ntfy-provision.env" = {
    restartUnits = [ "ntfy-sh.service" ];
    content = ''
      NTFY_AUTH_USERS=publisher:${config.sops.placeholder.ntfy-publisher-password-hash}:admin
      NTFY_AUTH_TOKENS=publisher:${config.sops.placeholder.ntfy-publisher-token}:workstation-agent-notify
      NTFY_AUTH_ACCESS=everyone:${config.sops.placeholder.ntfy-agents-channel}:ro
    '';
  };

  systemd.services.ntfy-sh.serviceConfig.EnvironmentFile = [
    config.sops.templates."ntfy-provision.env".path
  ];

  nori.harden.ntfy-sh = { };

  /*
    The alert endpoint is declared by manifests/server.nix. Open the
    backend port on the tailnet so Caddy can reach it.
  */
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8081 ];

  nori.backups.ntfy.skip = "Hub on appliance host (pi). Pi flash anti-write posture; auth db tiny (one publisher row) and reprovisioned declaratively from sops on every ntfy-sh start, so it's recreated automatically if lost.";
}
