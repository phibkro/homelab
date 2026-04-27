# Backup cluster — coupled.
#
# Three modules that share the data-durability infrastructure:
#   * restic.nix  — cross-cutting restic infra (sops password,
#                   /var/backup tmpfile, weekly + monthly check timers
#                   that iterate every nori.backups.<n>). Per-repo
#                   declarations live in service modules via the
#                   nori.backups abstraction (see modules/lib/backup.nix).
#   * verify.nix  — quarterly restore drill + manual deep-audit
#                   variant. Verifies that backups are *restorable*,
#                   not just *recorded*.
#   * btrbk.nix   — daily root + media btrfs subvolume snapshots,
#                   independent of restic but conceptually backup.
#
# All three share the OneTouch USB drive at /mnt/backup, the
# restic-password sops secret, and the notify@ template (failures
# alert via ntfy.sh). The cluster must be deployed together for
# the verification cadence to make sense.
_: {
  imports = [
    ./btrbk.nix
    ./restic.nix
    ./verify.nix
  ];
}
