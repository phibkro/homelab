{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Cross-cutting restic infrastructure: the shared password secret,
  # the /var/backup tmpfiles rule that Pattern C2 prepareCommands
  # write into, and the weekly + monthly verification timers that
  # iterate over every repo declared via `nori.backups`.
  #
  # Per-repo declarations live in the service modules they belong
  # to (`nori.backups.sonarr` in sonarr.nix, etc.) — see
  # modules/lib/backup.nix for the abstraction. The non-service-tied
  # repos (user-data for /home + /srv/share, media-irreplaceable for
  # /mnt/media subvolumes + Immich's Pattern B dump dir) are
  # declared at the bottom of this file because they don't belong
  # to any one service module.
  #
  # Repository: /mnt/backup is the OneTouch ext4 mount (formatted via
  # hosts/nori-station/disko-onetouch.nix). USB-attached spinning HDD
  # on nori-station — different physical drive from the IronWolf data
  # disk and the SN750 root disk, but same chassis / same PSU / same
  # USB hub. Failure-domain independence is partial: protects against
  # single-drive failure, not whole-machine loss. nori-pi (local fast
  # restore, when the SSD lands) and Hetzner Storage Box (off-site,
  # reactive) remain on the roadmap as additional repos.

  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/backup 0755 root root -"
  ];

  # ---------------------------------------------------------------------
  # Backup verification cadence (DESIGN.md L390-398).
  #
  # Two timers in addition to the daily backup runs:
  #   weekly  — `restic check`               (metadata only, fast)
  #   monthly — `restic check --read-data-subset=10%`
  #             (samples 10% of pack data; covers 100% over ~10 months)
  #
  # Both iterate every repo declared via `nori.backups`. Either step
  # failing for any repo trips OnFailure → notify@ → ntfy.sh urgent
  # alert. A backup that succeeds-but-rots silently is the failure
  # mode this guards against.
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
      for name in ${
        lib.concatStringsSep " " (
          lib.attrNames (lib.filterAttrs (_: cfg: cfg.paths != null) config.nori.backups)
        )
      }; do
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
      for name in ${
        lib.concatStringsSep " " (
          lib.attrNames (lib.filterAttrs (_: cfg: cfg.paths != null) config.nori.backups)
        )
      }; do
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

  # ---------------------------------------------------------------------
  # Non-service-tied backup repos. Service-specific repos live in the
  # respective service modules (modules/server/<name>.nix).

  # User data: /home/nori personal stuff + /srv/share dumping ground.
  # Both currently empty; declared now so they're backed up the
  # moment anything lands.
  nori.backups.user-data = {
    paths = [
      "/home"
      "/srv/share"
    ];
    timer = "*-*-* 03:00:00";
  };

  # Irreplaceable media: photos, home-videos, projects, archive, library.
  # Streaming excluded by tier policy. archive is mostly immutable so
  # daily restic runs are nearly-free (incremental dedup); library
  # (curated books + comics, hand-uploaded) is treated the same.
  # /var/lib/immich/backups is Immich's Pattern B SQL dumps — Immich's
  # own scheduled backup writes to this path (enable in admin web UI:
  # Settings → Administration → Backup → Database Dump Settings),
  # restic picks it up here as the second half of the consistent
  # point-in-time restore plan (per DESIGN.md L283-289).
  nori.backups.media-irreplaceable = {
    paths = [
      "/mnt/media/photos"
      "/mnt/media/home-videos"
      "/mnt/media/projects"
      "/mnt/media/archive"
      "/mnt/media/library"
      "/var/lib/immich/backups"
    ];
    timer = "*-*-* 03:30:00";
  };
}
