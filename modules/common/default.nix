{ config, ... }:

/**
  Universal NixOS bits every host imports regardless of role.

  Two distinct groupings live inside this folder:

   - `base.nix` / `users.nix` / `tailscale.nix` / `sops.nix` —
     baseline OS-level config (locale, sshd, the `nori` operator
     user, tailnet daemon, sops machinery).
   - `../infra/<concern>/` — PaaS layer (storage / networking /
     access / backup / capabilities / observability) exposing
     `nori.<X>` options. Hosts produce context (`nori.hosts`
     registry, `nori.gpu` hardware capabilities, `nori.fs`
     filesystem layout); workloads in `modules/services/`
     consume context and contribute declarations (`nori.lanRoutes`,
     `nori.backups`, `nori.harden`) which infra generators
     interpret.

  Topology: the `nori.hosts` registry is populated in
  `modules/machines/default.nix`'s `identityFor` (single source of
  truth — every host evals the same topology). The schema lives at
  `modules/infra/hosts.nix`.
*/
{
  imports = [
    ./base.nix
    ./users.nix
    ./tailscale.nix
    ./sops.nix

    # Infra layer — the PaaS concerns + their schemas.
    ../infra/hosts.nix
    ../infra/storage
    ../infra/networking
    ../infra/access
    ../infra/backup
    ../infra/capabilities
    ../infra/observability

    # Top-level policies + leaf config.
    ../infra/placement.nix
    ../infra/restart-policy.nix
    ../infra/tailnet-appliance.nix
    ../infra/motd.nix # codename banner + live MOTD on login
  ];

  /**
    Pi-central entry plane (ADR-0003 + ADR-0004): family-tier
    traffic lands on pi's Caddy via wildcard `*.${nori.domain}`
    LE cert. The lan-route default would otherwise derive lanIp
    from the unique workhorse with a non-null lanIp (workstation)
    and route every client through workstation's now-retired
    Caddy.
  */
  nori.lanIp = config.nori.hosts.pi.lanIp;
}
