{ config, ... }:

let
  site = import ../../../inventory/site.nix;
in

/**
  Universal NixOS bits every host imports regardless of role.

  Two distinct groupings live inside this folder:

   - `base.nix` / `users.nix` / `tailscale.nix` / `sops.nix` —
     baseline OS-level config (locale, sshd, the `nori` operator
     user, tailnet daemon, sops machinery).
   - `../<concern>/` — PaaS layer (storage / networking /
     access / backup / capabilities / observability) exposing
     `nori.<X>` options. Hosts produce context (`nori.hosts`
     registry, `nori.gpu` hardware capabilities, `nori.fs`
     filesystem layout); workloads in `services/`
     consume context and contribute declarations (`nori.lanRoutes`,
     `nori.backups`, `nori.harden`) which infra generators
     interpret.

  Topology: the `nori.hosts` registry is populated in
  `inventory/hosts.nix` (single source of
  truth — every host evals the same topology). The schema lives at
  `infra/common/nixos/hosts.nix`.
*/
{
  imports = [
    ./base.nix
    ../../../users/nori/identity.nix
    ./ssh.nix
    ../../../services/tailscale/nixos.nix
    ./sops.nix

    # Infra layer — the PaaS concerns + their schemas.
    ./hosts.nix
    ./inventory.nix
    ./storage
    ./routes.nix
    ./backup.nix
    ./service-hardening.nix
    ./alerts.nix
    ../../../services/agent-fix/nixos.nix

    # Top-level policies + leaf config.
    ./restart-policy.nix
    ./motd.nix # codename banner + live MOTD on login
  ];

  /**
    Pi-central entry plane (ADR-0003 + ADR-0004): family-tier
    traffic lands on pi's Caddy via wildcard `*.${nori.domain}`
    LE cert. The lan-route default would otherwise derive lanIp
    from the unique workhorse with a non-null lanIp (workstation)
    and route every client through workstation's now-retired
    Caddy.
  */
  nori.lanIp = config.nori.hosts.${site.entryPlaneHost}.lanIp;
}
