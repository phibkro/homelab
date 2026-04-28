_: {
  # The "common" concern — every host needs this regardless of role.
  # base.nix/users.nix/tailscale.nix/sops.nix are universal infra; the
  # ../lib/*.nix modules expose options (nori.lanRoutes, nori.backups)
  # that any module on the host can populate, so they're imported here
  # rather than per-host.
  imports = [
    ./base.nix
    ./users.nix
    ./tailscale.nix
    ./sops.nix
    ../lib/lan-route.nix
    ../lib/backup.nix
    ../lib/gpu.nix
  ];
}
