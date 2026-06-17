{
  config,
  lib,
  ...
}:

lib.mkMerge [
  {
    nori.services.beszel-agent.tags = [ "observability" ];

    /**
      Caddy-gated so hosts running the agent without Caddy (Pi itself)
      don't pollute their lanRoutes — Pi's Blocky stays in pure
      forwarder mode and the canonical service host owns *.nori.lan.

      Web-UI-managed OIDC (PocketBase per-collection OAuth2 — moved out
      of system-wide settings in PocketBase 0.36+). The lanRoute generates
      the Authelia client + sops secret; the operator pastes the raw
      secret into the `users` collection's OAuth2 config on Pi.

      First-run setup (resumes the paused-mid-flow setup tracked in
      CLAUDE.md Outstanding):
        1. just generate-oidc-key metrics                          (regenerate)
        2. sops secrets/secrets.yaml — paste both values
        3. just rebuild
        4. https://metrics.nori.lan → log in as admin → Collections (DB
           icon) → users → ⚙ Options → OAuth2 tab:
             Provider:      OIDC
             Client ID:     metrics
             Client Secret: cat /run/secrets/oidc-metrics-client-secret
                             (sudo on Pi)
             Auth URL:      https://auth.nori.lan/api/oidc/authorization
             Token URL:     https://auth.nori.lan/api/oidc/token
             UserInfo URL:  https://auth.nori.lan/api/oidc/userinfo
             Display Name:  Authelia
           Save. The redirect URI in Authelia (auto-set by lan-route) is
           https://metrics.nori.lan/api/oauth2-redirect — PocketBase's
           default OAuth2 callback path.
    */
    nori.lanRoutes = lib.mkIf config.services.caddy.enable {
      metrics = {
        port = 8090;
        runsOn = "pi";
        monitor = { };
        audience = "operator";
        oidc = {
          clientName = "Beszel";
          redirectPath = "/api/oauth2-redirect";
        };
        dashboard = {
          title = "Beszel";
          icon = "sh:beszel";
          group = "Admin";
          description = "System metrics (CPU / RAM / disk / GPU)";
        };
      };
    };
  }
  (lib.mkIf config.nori.services.beszel-agent.enabled {
    /**
      beszel-agent — per-host metrics collector. Hub on pi pulls
      over tailnet (cross-host: hub-host opens an outbound TCP connection
      to each agent's port 45876). Stateless from this host's perspective:
      the hub's SSH public key from sops, metrics streamed in-memory.

      Single shared `beszel-hub-pubkey` sops secret — Beszel uses a
      symmetric trust model where every agent installs the hub's public
      key as KEY. Operator mints the hub keypair via the Beszel admin UI;
      the same pubkey lands on every agent.
    */

    sops.secrets.beszel-hub-pubkey = {
      mode = "0400";
      /*
        No `group` set: systemd reads EnvironmentFile as PID 1 and injects
        KEY into the DynamicUser process — beszel-agent never reads the
        file directly, so SupplementaryGroups=keys is unneeded.
      */
    };

    services.beszel.agent = {
      enable = true;
      environmentFile = config.sops.secrets.beszel-hub-pubkey.path;
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 45876 ];

    nori.harden.beszel-agent = { };

    /*
      PrivateDevices override: upstream sets it true (when smartmon is
      off), which hides /dev/nvidia*. On hosts that opt into NVIDIA via
      nori.gpu.nvidiaDevices (see modules/infra/capabilities/gpu.nix) the agent surfaces
      driver telemetry via nvidia-smi, so we expose /dev/* there. The
      rest of the hardening (ProtectKernel*, SystemCallFilter,
      RestrictSUIDSGID, NoNewPrivileges, PrivateUsers) still applies —
      only the device namespace loosens.
    */
    systemd.services.beszel-agent.serviceConfig.PrivateDevices = lib.mkIf (
      config.nori.gpu.nvidiaDevices != [ ]
    ) (lib.mkForce false);

    nori.backups.beszel-agent.skip = "Stateless — SSH key from sops, metrics streamed to hub (no local persistence).";
  })
]
