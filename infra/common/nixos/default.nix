{ ... }:

/**
  Universal NixOS bits every host imports regardless of role.

  Two distinct groupings live inside this folder:

   - `base.nix` / `users.nix` / `tailscale.nix` / `sops.nix` —
     baseline OS-level config (locale, sshd, the `nori` operator
     user, tailnet daemon, sops machinery).
   - `../<concern>/` — PaaS options for storage, access, backup,
     capabilities, and observability.

  The pure inventory compiles workload declarations before NixOS and Ansible
  adapters consume them. Its typed NixOS projection lives in
  `infra/common/nixos/inventory.nix`.
*/
{
  imports = [
    ./base.nix
    ../../../users/nori/identity.nix
    ./ssh.nix
    ./wifi.nix
    ../../../services/tailscale/nixos.nix
    ./sops.nix

    # Infra layer — the PaaS concerns + their schemas.
    ./inventory.nix
    ./storage
    ./workload-oidc.nix
    ./backup.nix
    ./service-hardening.nix
    ./alerts.nix
    ../../../services/agent-fix/nixos.nix

    # Top-level policies + leaf config.
    ./restart-policy.nix
    ./motd.nix # codename banner + live MOTD on login
  ];

}
