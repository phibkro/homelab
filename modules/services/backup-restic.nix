{
  config,
  lib,
  pkgs,
  ...
}:

{
  # restic backup module — Pattern A from DESIGN.md L210-289.
  #
  # Pattern A is filesystem-only: just point restic at paths. Used here
  # for /home, /srv/share, and the irreplaceable IronWolf subvolumes
  # (photos, home-videos, projects). Streaming media is intentionally
  # excluded (DESIGN tier table: re-derivable, no backup).
  #
  # Patterns B (Immich's built-in dump) and C (external dump pre-restic
  # for Postgres/SQLite) land alongside the services that need them
  # — Immich, Open WebUI, etc.
  #
  # Repository: /mnt/backup is the OneTouch ext4 mount (formatted via
  # hosts/nori-station/disko-onetouch.nix). USB-attached spinning HDD
  # on nori-station — different physical drive from the IronWolf data
  # disk and the SN750 root disk, but same chassis / same PSU / same
  # USB hub. Failure-domain independence is partial: protects against
  # single-drive failure, not whole-machine loss. nori-pi (local fast
  # restore, when the SSD lands) and Hetzner Storage Box (off-site,
  # reactive) remain on the roadmap as additional repos:
  #
  #   - nori-pi (local fast restore): SFTP repository
  #     repository = "sftp:nori-pi:/mnt/backup/<name>";
  #
  #   - Hetzner Storage Box (off-site): also SFTP
  #     repository = "sftp:u123456@u123456.your-storagebox.de:<name>";
  #     extraOptions = [ "sftp.command='ssh -p 23 ...'" ];

  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/backup 0755 root root -"
  ];

  # Wire each restic backup unit's failure into ntfy via the template
  # in modules/services/ntfy.nix. The names must match the systemd
  # units the restic module generates: restic-backups-<job>.service.
  systemd.services.restic-backups-user-data.unitConfig.OnFailure = [
    "notify@restic-backups-user-data.service"
  ];
  systemd.services.restic-backups-media-irreplaceable.unitConfig.OnFailure = [
    "notify@restic-backups-media-irreplaceable.service"
  ];
  systemd.services.restic-backups-open-webui.unitConfig.OnFailure = [
    "notify@restic-backups-open-webui.service"
  ];
  systemd.services.restic-backups-vaultwarden.unitConfig.OnFailure = [
    "notify@restic-backups-vaultwarden.service"
  ];

  # ---------------------------------------------------------------------
  # Backup verification cadence (DESIGN.md L390-398).
  #
  # Two timers in addition to the daily backup runs:
  #   weekly  — `restic check`               (metadata only, fast)
  #   monthly — `restic check --read-data-subset=10%`
  #             (samples 10% of pack data; covers 100% over ~10 months)
  #
  # Both iterate the same three repos. Either step failing for any
  # repo trips OnFailure → notify@ → ntfy.sh urgent alert. A backup
  # that succeeds-but-rots silently is the failure mode this guards
  # against; running `restic backup` daily without ever reading the
  # repo back is the easiest way to discover bit-rot during a real
  # restore.
  #
  # The wrapper iterates serially (USB HDD; concurrent reads thrash).
  # Failures don't short-circuit — every repo gets attempted so a
  # corrupt repo doesn't hide rot in the others.
  systemd.services.restic-check-weekly = {
    description = "Weekly metadata check of all restic repositories";
    after = [ "mnt-backup.mount" ];
    requires = [ "mnt-backup.mount" ];
    unitConfig.OnFailure = [ "notify@restic-check-weekly.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
    script = ''
      fail=0
      for name in user-data media-irreplaceable open-webui vaultwarden; do
        echo "[$name] restic check"
        if ! ${pkgs.restic}/bin/restic -r /mnt/backup/$name check; then
          echo "[$name] FAILED"
          fail=1
        fi
      done
      exit $fail
    '';
  };

  systemd.timers.restic-check-weekly = {
    description = "Weekly metadata check of all restic repositories";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 05:00:00";
      Persistent = true;
    };
  };

  systemd.services.restic-check-monthly = {
    description = "Monthly read-10% data sample check of all restic repositories";
    after = [ "mnt-backup.mount" ];
    requires = [ "mnt-backup.mount" ];
    unitConfig.OnFailure = [ "notify@restic-check-monthly.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
    script = ''
      fail=0
      for name in user-data media-irreplaceable open-webui vaultwarden; do
        echo "[$name] restic check --read-data-subset=10%"
        if ! ${pkgs.restic}/bin/restic -r /mnt/backup/$name check --read-data-subset=10%; then
          echo "[$name] FAILED"
          fail=1
        fi
      done
      exit $fail
    '';
  };

  systemd.timers.restic-check-monthly = {
    description = "Monthly read-10% data sample check of all restic repositories";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-01 06:00:00"; # 1st of each month
      Persistent = true;
    };
  };

  services.restic.backups = {
    # User data: /home/nori personal stuff + /srv/share dumping ground.
    # Both currently empty; declared now so they're backed up the
    # moment anything lands.
    user-data = {
      paths = [
        "/home"
        "/srv/share"
      ];
      repository = "/mnt/backup/user-data";
      passwordFile = config.sops.secrets.restic-password.path;
      initialize = true;
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
    };

    # Irreplaceable media: photos, home-videos, projects, archive, library.
    # Streaming excluded by tier policy. archive is mostly immutable so
    # daily restic runs are nearly-free (incremental dedup); library
    # (curated books + comics, hand-uploaded) is treated the same.
    # /var/lib/immich/backups is Immich's Pattern B SQL dumps —
    # Immich's own scheduled backup writes to this path, restic
    # picks it up here as the second half of the consistent
    # point-in-time restore plan (per DESIGN.md L283-289).
    media-irreplaceable = {
      paths = [
        "/mnt/media/photos"
        "/mnt/media/home-videos"
        "/mnt/media/projects"
        "/mnt/media/archive"
        "/mnt/media/library"
        "/var/lib/immich/backups"
      ];
      repository = "/mnt/backup/media-irreplaceable";
      passwordFile = config.sops.secrets.restic-password.path;
      initialize = true;
      timerConfig = {
        OnCalendar = "*-*-* 03:30:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
    };

    # Open WebUI state — Pattern C2 from DESIGN.md L258-275.
    # SQLite needs a logical .backup before filesystem snapshot to
    # produce a consistent dump. The guard handles the case where
    # the DB doesn't exist yet (first run, before any user has
    # registered).
    open-webui = {
      paths = [
        "/var/lib/open-webui"
        "/var/backup/open-webui"
      ];
      repository = "/mnt/backup/open-webui";
      passwordFile = config.sops.secrets.restic-password.path;
      initialize = true;
      backupPrepareCommand = ''
        if [ -f /var/lib/open-webui/webui.db ]; then
          mkdir -p /var/backup/open-webui
          ${pkgs.sqlite}/bin/sqlite3 /var/lib/open-webui/webui.db \
            ".backup '/var/backup/open-webui/webui.db'"
        fi
      '';
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
    };

    # Vaultwarden state — Pattern C2, same shape as open-webui.
    # Backed up under its own repo (rather than folded into user-data)
    # because (a) the prepareCommand is per-repo and (b) password-store
    # data warrants its own retention/recovery story even when the
    # disk-level dedup makes the cost negligible.
    vaultwarden = {
      paths = [
        "/var/lib/vaultwarden"
        "/var/backup/vaultwarden"
      ];
      repository = "/mnt/backup/vaultwarden";
      passwordFile = config.sops.secrets.restic-password.path;
      initialize = true;
      backupPrepareCommand = ''
        if [ -f /var/lib/vaultwarden/db.sqlite3 ]; then
          mkdir -p /var/backup/vaultwarden
          ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
            ".backup '/var/backup/vaultwarden/db.sqlite3'"
        fi
      '';
      timerConfig = {
        OnCalendar = "*-*-* 04:30:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
    };
  };
}
