{
  config,
  lib,
  pkgs,
  ...
}:

{
  # beszel — lightweight metrics hub for system monitoring (CPU, RAM,
  # disk, network, GPU). Per DESIGN.md L455 the chosen metrics tool
  # over heavier options like Prometheus/Grafana for a homelab.
  #
  # Two halves:
  #   hub    — web UI + storage of historical metrics (this module)
  #   agent  — collects + reports metrics to the hub (separate module
  #            once the hub-issued auth key is captured into sops)
  #
  # First-time setup after activation:
  #   1. Connect to http://nori-station.saola-matrix.ts.net:8090
  #   2. Create admin user (form on first connect)
  #   3. Dashboard → Add System → "nori-station" → hub generates a
  #      key + install command. Capture the key into sops as
  #      `beszel-agent-key` and add the agent module in a follow-up.
  #   4. Configure alerts in the web UI; route to the ntfy.sh channel
  #      (web UI → Settings → Notifications → Webhook URL =
  #      https://ntfy.sh/<your-channel> with appropriate headers)
  #
  # State (sqlite db, history) at /var/lib/beszel.

  services.beszel = {
    hub = {
      enable = true;
      host = "0.0.0.0";
      port = 8090;
      # No openFirewall option exists on this module; the explicit
      # networking.firewall.interfaces."tailscale0" rule below opens
      # 8090 on the tailnet only. Global firewall stays default-deny.
    };
  };

  # OIDC SSO via Authelia: USER_CREATION=true lets Beszel create
  # accounts on first OIDC login (default is "deny unknown user", which
  # makes OIDC unusable for new users). DISABLE_PASSWORD_AUTH stays
  # off — keeps the local-password fallback as recovery if Authelia
  # itself is down.
  systemd.services.beszel-hub.environment = {
    USER_CREATION = "true";
  };

  systemd.services.beszel-hub.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
  };

  # Exposed at https://metrics.nori.lan via Caddy. Auto-monitored.
  nori.lanRoutes.metrics = {
    port = 8090;
    monitor = { };
  };
}
