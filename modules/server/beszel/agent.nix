{
  config,
  lib,
  pkgs,
  ...
}:

let
  secretName = "beszel-agent-key-${config.networking.hostName}";
in
{
  # beszel-agent — per-host metrics collector. Hub on pi pulls
  # over tailnet (cross-host: hub-host opens an outbound TCP connection
  # to each agent's port 45876). Stateless from this host's perspective:
  # SSH key from sops, metrics streamed in-memory.
  #
  # Every host that imports this module needs a matching
  # `beszel-agent-key-<hostname>` entry in secrets/secrets.yaml.

  sops.secrets.${secretName} = {
    mode = "0400";
    # No `group` set: systemd reads EnvironmentFile as PID 1 and injects
    # KEY into the DynamicUser process — beszel-agent never reads the
    # file directly, so SupplementaryGroups=keys is unneeded.
  };

  services.beszel.agent = {
    enable = true;
    # Default port 45876, listening on all interfaces. Hub-host
    # connects over tailnet — needs the port open on tailscale0
    # (handled below) since cross-host this isn't localhost anymore.
    environmentFile = config.sops.secrets.${secretName}.path;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 45876 ];

  # Agent FS hardening on top of upstream's substantial systemd
  # profile (PrivateUsers, ProtectKernel*, ProtectSystem=strict,
  # SystemCallFilter). Default-deny FS namespace is the project-wide
  # baseline (nori.harden, modules/effects/harden.nix).
  nori.harden.beszel-agent = { };

  # PrivateDevices override: upstream sets it true (when smartmon is
  # off), which hides /dev/nvidia*. On hosts that opt into NVIDIA via
  # nori.gpu.nvidiaDevices (see modules/effects/gpu.nix) the agent surfaces
  # driver telemetry via nvidia-smi, so we expose /dev/* there. The
  # rest of the hardening (ProtectKernel*, SystemCallFilter,
  # RestrictSUIDSGID, NoNewPrivileges, PrivateUsers) still applies —
  # only the device namespace loosens.
  systemd.services.beszel-agent.serviceConfig.PrivateDevices = lib.mkIf (
    config.nori.gpu.nvidiaDevices != [ ]
  ) (lib.mkForce false);

  # Cross-host metrics URL: this host's Caddy (if running) reverse-
  # proxies https://metrics.nori.lan to the Pi-hosted hub at port 8090.
  # Gated on Caddy presence so that hosts running the agent without
  # Caddy (the Pi itself) don't pollute their lanRoutes registry — Pi's
  # Blocky stays in pure forwarder mode and the canonical service host
  # owns the *.nori.lan map.
  #
  # The hub-host coupling lives in the nori.hosts registry (single
  # source of truth — see modules/effects/hosts.nix). If the hub ever
  # relocates, update modules/common/topology.nix instead of editing
  # this file.
  # Web-UI-managed OIDC (PocketBase per-collection OAuth2 — moved out
  # of system-wide settings in PocketBase 0.36+). The lanRoute generates
  # the Authelia client + sops secret; the operator pastes the raw
  # secret into the `users` collection's OAuth2 config on Pi.
  #
  # First-run setup (resumes the paused-mid-flow setup tracked in
  # CLAUDE.md Outstanding):
  #   1. just oidc-key metrics                          (regenerate)
  #   2. sops secrets/secrets.yaml — paste both values
  #   3. just rebuild
  #   4. https://metrics.nori.lan → log in as admin → Collections (DB
  #      icon) → users → ⚙ Options → OAuth2 tab:
  #        Provider:      OIDC
  #        Client ID:     metrics
  #        Client Secret: cat /run/secrets/oidc-metrics-client-secret
  #                        (sudo on Pi)
  #        Auth URL:      https://auth.nori.lan/api/oidc/authorization
  #        Token URL:     https://auth.nori.lan/api/oidc/token
  #        UserInfo URL:  https://auth.nori.lan/api/oidc/userinfo
  #        Display Name:  Authelia
  #      Save. The redirect URI in Authelia (auto-set by lan-route) is
  #      https://metrics.nori.lan/api/oauth2-redirect — PocketBase's
  #      default OAuth2 callback path.
  nori.lanRoutes = lib.mkIf config.services.caddy.enable {
    metrics = {
      port = 8090;
      host = config.nori.hosts.pi.tailnetIp;
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

  # No on-disk state. SSH key from sops, metrics streamed to hub.
  nori.backups.beszel-agent.skip = "Stateless — SSH key from sops, metrics streamed to hub (no local persistence).";
}
