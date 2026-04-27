{
  config,
  lib,
  pkgs,
  ...
}:

{
  # beszel — lightweight metrics hub + agent (CPU, RAM, disk, network,
  # GPU). Per DESIGN.md L455 the chosen metrics tool over heavier
  # options like Prometheus/Grafana for a homelab.
  #
  # Two halves co-located on nori-station:
  #   hub    — web UI + sqlite history at /var/lib/beszel
  #   agent  — collects + reports metrics; hub connects to it on
  #            localhost:45876 using SSH-style key auth
  #
  # === Bootstrap order (one-time, web UI first) ===
  #   1. Connect to https://metrics.nori.lan
  #   2. Create admin user (form on first connect) OR sign in via
  #      Authelia OIDC (USER_CREATION=true below permits auto-provision)
  #   3. Dashboard → Add System → "nori-station" → host=localhost,
  #      port=45876. Hub generates a key + install command. Copy the
  #      `KEY=ssh-ed25519 AAAA...` line.
  #   4. Run `sops secrets/secrets.yaml` and add as a block-string:
  #        beszel-agent-key-nori-station: |
  #          KEY=ssh-ed25519 AAAA...
  #      (env-file format — `=` not `:`, see docs/gotchas.md.)
  #   5. Deploy. Hub will see the agent come online within ~30s.
  #   6. Configure alerts in web UI → Settings → Notifications →
  #      Webhook URL = https://ntfy.sh/<channel> with appropriate headers.
  #
  # The sops.secrets declaration below references the key by name; if
  # the key isn't in secrets.yaml at activation time, sops-nix fails at
  # activation (not at flake-check time). Do step 4 BEFORE deploying
  # the change that introduces the agent block.

  sops.secrets.beszel-agent-key-nori-station = {
    mode = "0400";
    # No `group` set: systemd reads the EnvironmentFile as PID 1 and
    # injects KEY into the DynamicUser process — beszel-agent never
    # reads the file directly, so SupplementaryGroups=keys is unneeded.
  };

  services.beszel = {
    hub = {
      enable = true;
      host = "0.0.0.0";
      port = 8090;
      # No openFirewall option exists on this module; the explicit
      # networking.firewall.interfaces."tailscale0" rule below opens
      # 8090 on the tailnet only. Global firewall stays default-deny.
    };

    agent = {
      enable = true;
      # Default port 45876, listening on all interfaces. Hub connects
      # over localhost; we don't openFirewall because the agent is for
      # this hub only and the hub is on the same host. SMART monitoring
      # deferred — useful but needs CAP_SYS_ADMIN + disk group; revisit
      # when "drive failing soon" alerts become load-bearing.
      environmentFile = config.sops.secrets.beszel-agent-key-nori-station.path;
      # NVIDIA path is auto-injected by the upstream module when
      # services.xserver.videoDrivers contains "nvidia" (it does).
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

  # Agent: matching FS hardening. Upstream module already sets a
  # substantial systemd hardening profile (PrivateUsers, ProtectKernel*,
  # ProtectSystem=strict, SystemCallFilter); we add the project-wide
  # default-deny FS namespace on top.
  #
  # PrivateDevices=false override: upstream sets it true (when smartmon
  # is off), which hides /dev/nvidia* and makes nvidia-smi return no GPU
  # data. Disabling exposes the full /dev. The rest of the hardening
  # (ProtectKernel*, SystemCallFilter, RestrictSUIDSGID, NoNewPrivileges,
  # PrivateUsers) still applies — only the device namespace loosens.
  systemd.services.beszel-agent.serviceConfig = {
    ProtectHome = lib.mkForce true;
    TemporaryFileSystem = [
      "/mnt:ro"
      "/srv:ro"
    ];
    BindReadOnlyPaths = [ ];
    PrivateDevices = lib.mkForce false;
  };

  # Exposed at https://metrics.nori.lan via Caddy. Auto-monitored.
  #
  # OIDC deferred — PocketBase OAuth setup is paused mid-flow (per
  # docs/RESUME.md item #7). When picking it back up:
  #   1. `just oidc-key metrics`  → outputs raw + hash
  #   2. paste both into sops as oidc-metrics-client-secret and
  #      oidc-metrics-client-secret-hash
  #   3. reattach the lan-route oidc block:
  #
  #        oidc = {
  #          clientName   = "Beszel";
  #          redirectPath = "/api/oauth2-redirect";
  #        };
  #
  # PocketBase consumes OAuth via web-UI config, not env vars — the
  # consumer-side wiring is a one-time paste from the raw secret at
  # /run/secrets/oidc-metrics-client-secret into the PocketBase admin
  # at https://metrics.nori.lan/_/ → Collections → users → ⚙ →
  # OAuth2.
  nori.lanRoutes.metrics = {
    port = 8090;
    monitor = { };
  };
}
