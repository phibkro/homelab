{ config, ... }: {
  # The "common" concern — every host needs this regardless of role.
  # base.nix/users.nix/tailscale.nix/sops.nix are universal infra; the
  # ../effects/*.nix modules expose `nori.<X>` options that form a
  # Reader + collected-Writer effect interface. Hosts produce
  # context (nori.hosts registry, nori.gpu hardware capabilities,
  # nori.fs filesystem layout); services consume context and
  # contribute declarations (nori.lanRoutes, nori.backups, nori.harden)
  # which generators in the effect modules interpret.
  #
  # The nori.hosts registry is *populated* in flake.nix's `hostRegistry`
  # (single source of truth — every host evals the same topology). The
  # *schema* lives in modules/effects/hosts.nix below.
  imports = [
    ./base.nix
    ./users.nix
    ./tailscale.nix
    ./sops.nix
    ./vector.nix
    ../effects/hosts.nix
    ../effects/fs.nix
    ../effects/lan-route.nix
    ../effects/service-placement.nix
    ../effects/backup.nix
    ../effects/gpu.nix
    ../effects/harden.nix
    ../effects/gatus-probe.nix
    ../effects/replication.nix
    ../effects/restart-policy.nix
    ../effects/rust-motd.nix # codename banner + live MOTD on login
    ../effects/tailnet-appliance.nix
  ];

  # Pi-central entry plane (ADR-0003 + ADR-0004): family-tier traffic
  # lands on pi's Caddy via wildcard `*.${nori.domain}` LE cert. The
  # lan-route default would otherwise derive lanIp from the unique
  # workhorse with a non-null lanIp (workstation) and route every
  # client through workstation's now-retired Caddy.
  nori.lanIp = config.nori.hosts.pi.lanIp;
}
