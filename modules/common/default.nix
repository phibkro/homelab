_: {
  # The "common" concern — every host needs this regardless of role.
  # base.nix/users.nix/tailscale.nix/sops.nix are universal infra; the
  # ../lib/*.nix modules expose options (nori.lanRoutes, nori.backups,
  # nori.hosts, nori.gpu, nori.harden) that any module on the host can
  # populate.
  #
  # The nori.hosts registry is *populated* in flake.nix's `hostRegistry`
  # (single source of truth — every host evals the same topology). The
  # *schema* lives in modules/lib/hosts.nix below.
  imports = [
    ./base.nix
    ./users.nix
    ./tailscale.nix
    ./sops.nix
    ../lib/hosts.nix
    ../lib/lan-route.nix
    ../lib/backup.nix
    ../lib/gpu.nix
    ../lib/harden.nix
  ];
}
