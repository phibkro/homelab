# Backup cluster — coupled. Three modules share the OneTouch USB
# mount at /mnt/backup, the restic-password sops secret, and the
# notify@ template; must deploy together for the verification cadence
# (restic checks + restore drills in verify.nix) to make sense.
# Per-repo declarations live in service modules via nori.backups
# (see modules/effects/backup.nix for the abstraction).
_: {
  imports = [
    ./btrbk.nix
    ./restic.nix
    ./verify.nix
  ];
}
