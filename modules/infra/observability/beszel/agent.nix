{
  config,
  lib,
  ...
}:

{
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
}
