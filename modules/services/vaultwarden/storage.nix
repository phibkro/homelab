{
  config,
  lib,
  pkgs,
  ...
}:

# Vaultwarden — storage concern.
#
# Pattern C2 — VACUUM INTO snapshot before restic. Static
# `vaultwarden` user (not DynamicUser), so /var/lib/vaultwarden is
# a real directory. The `if` guards the bootstrap case where the
# DB doesn't exist yet.

lib.mkIf config.nori.services.vaultwarden.enabled {
  nori.backups.vaultwarden = {
    include = [
      "/var/lib/vaultwarden"
      "/var/backup/vaultwarden"
    ];
    prepareCommand = ''
      if [ -f /var/lib/vaultwarden/db.sqlite3 ]; then
        mkdir -p /var/backup/vaultwarden
        # VACUUM INTO + PRAGMA busy_timeout — see the long-form
        # rationale in navidrome.nix. The sqlite3 CLI's `.backup`
        # ignores busy_timeout, so the previous `.timeout 30000` was
        # a no-op. Vaultwarden writes on every sync/login.
        # Serialize concurrent prep — onetouch + mp510 race fix.
        # See navidrome.nix for the long form.
        (
          ${pkgs.util-linux}/bin/flock -x 9
          rm -f /var/backup/vaultwarden/db.sqlite3.tmp
          ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
            "PRAGMA busy_timeout = 30000;" \
            "VACUUM INTO '/var/backup/vaultwarden/db.sqlite3.tmp';"
          mv /var/backup/vaultwarden/db.sqlite3.tmp /var/backup/vaultwarden/db.sqlite3
        ) 9>/var/backup/vaultwarden/.prep.lock
      fi
    '';
    timer = "*-*-* 04:30:00";
  };
}
