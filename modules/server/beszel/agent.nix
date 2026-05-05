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
  # beszel-agent — per-host metrics collector. Hub on nori-pi pulls
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
  nori.lanRoutes = lib.mkIf config.services.caddy.enable {
    metrics = {
      port = 8090;
      host = config.nori.hosts.nori-pi.tailnetIp;
      monitor = { };
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
