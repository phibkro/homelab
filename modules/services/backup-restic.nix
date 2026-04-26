{ config, lib, pkgs, ... }:

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
  # PLACEHOLDER REPOSITORY: /var/backup/restic-local lives on the same
  # NVMe as the data it's "backing up." This is not a backup — it's
  # plumbing scaffolding to validate the restic pipeline, secret
  # decryption, and timer activation before nori-pi exists. When the
  # real targets land:
  #
  #   - nori-pi (local fast restore): SFTP repository
  #     repository = "sftp:nori-pi:/mnt/backup/<name>";
  #
  #   - Hetzner Storage Box (off-site): also SFTP
  #     repository = "sftp:u123456@u123456.your-storagebox.de:<name>";
  #     extraOptions = [ "sftp.command='ssh -p 23 ...'" ];
  #
  # When that swap happens: drop the local placeholder, add per-job
  # repositories for both Pi and Hetzner per DESIGN L295-303 retention
  # split, and keep the same paths.

  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/backup             0755 root root -"
    "d /var/backup/restic-local 0700 root root -"
  ];

  services.restic.backups = {
    # User data: /home/nori personal stuff + /srv/share dumping ground.
    # Both currently empty; declared now so they're backed up the
    # moment anything lands.
    user-data = {
      paths = [
        "/home"
        "/srv/share"
      ];
      repository = "/var/backup/restic-local/user-data";
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

    # Irreplaceable media: photos, home-videos, projects. Streaming
    # excluded by tier policy.
    media-irreplaceable = {
      paths = [
        "/mnt/media/photos"
        "/mnt/media/home-videos"
        "/mnt/media/projects"
      ];
      repository = "/var/backup/restic-local/media-irreplaceable";
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
  };
}
