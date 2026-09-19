{
  config,
  lib,
  ...
}:

{
  /**
    beszel-agent — per-host metrics collector. Hub on Pi pulls over
    tailnet. The agent trusts the hub's SSH public key. This is a public
    trust anchor, not confidential key material, so it remains visible in
    source and the Nix store instead of widening SOPS recipient access.
  */

  services.beszel.agent = {
    enable = true;
    environment.KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF2lWbtgJ4ahX4/ceH3PTHJ8xgbteUj+OLFtXYWbXBcI";
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 45876 ];

  nori.harden.beszel-agent = { };

  /*
    PrivateDevices override: upstream sets it true (when smartmon is
    off), which hides /dev/nvidia*. On hosts that opt into NVIDIA via
    nori.gpu.nvidiaDevices (see infra/common/nixos/gpu.nix) the agent surfaces
    driver telemetry via nvidia-smi, so we expose /dev/* there. The
    rest of the hardening (ProtectKernel*, SystemCallFilter,
    RestrictSUIDSGID, NoNewPrivileges, PrivateUsers) still applies —
    only the device namespace loosens.
  */
  systemd.services.beszel-agent.serviceConfig.PrivateDevices = lib.mkIf (
    config.nori.gpu.nvidiaDevices != [ ]
  ) (lib.mkForce false);

  nori.backups.beszel-agent.skip = "Stateless — hub public key is declarative and metrics stream to the hub.";
}
