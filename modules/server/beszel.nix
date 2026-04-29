{
  config,
  lib,
  pkgs,
  ...
}:

{
  # beszel — station runs the agent only; the hub lives on nori-pi
  # (see hosts/nori-pi/default.nix). Pattern matches Gatus-on-Pi:
  # observability infra runs on the appliance host so it survives
  # outages of the workhorse host. When station hangs, the hub on
  # Pi keeps recording metrics up to the last poll — useful for
  # post-incident forensics ("what was CPU/mem doing right before
  # the freeze?"). Migrated 2026-04-29.

  sops.secrets.beszel-agent-key-nori-station = {
    mode = "0400";
    # No `group` set: systemd reads the EnvironmentFile as PID 1 and
    # injects KEY into the DynamicUser process — beszel-agent never
    # reads the file directly, so SupplementaryGroups=keys is unneeded.
  };

  services.beszel.agent = {
    enable = true;
    # Default port 45876, listening on all interfaces. Hub on Pi
    # connects over tailnet — needs the port open on tailscale0
    # (handled below) since cross-host this isn't localhost anymore.
    environmentFile = config.sops.secrets.beszel-agent-key-nori-station.path;
    # NVIDIA path is auto-injected by the upstream module when
    # services.xserver.videoDrivers contains "nvidia" (it does).
  };

  # Open agent port 45876 on tailnet so the Pi-hosted hub can poll.
  # Localhost-bound was sufficient when hub was co-located; cross-host
  # now requires explicit tailnet exposure.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 45876 ];

  # Agent FS hardening. Upstream module already sets a substantial
  # systemd hardening profile (PrivateUsers, ProtectKernel*,
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

  # Caddy vhost for https://metrics.nori.lan reverse-proxies cross-host
  # to Pi's hub at 100.100.71.3:8090. The user-facing URL stays the same;
  # Authelia OIDC (when re-enabled) keeps working since it operates on
  # the hostname not the backend.
  nori.lanRoutes.metrics = {
    port = 8090;
    host = "100.100.71.3"; # nori-pi tailnet IP
    monitor = { };
  };

  # Beszel hub's PocketBase sqlite is now on Pi — its backup config
  # lives in hosts/nori-pi/default.nix.
  nori.backups.beszel.skip = "Hub moved to nori-pi 2026-04-29; backup intent declared on Pi side.";
}
