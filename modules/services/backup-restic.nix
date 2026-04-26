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

  # Wire each restic backup unit's failure into ntfy via the template
  # in modules/services/ntfy.nix. The names must match the systemd
  # units the restic module generates: restic-backups-<job>.service.
  systemd.services.restic-backups-user-data.unitConfig.OnFailure =
    [ "notify@restic-backups-user-data.service" ];
  systemd.services.restic-backups-media-irreplaceable.unitConfig.OnFailure =
    [ "notify@restic-backups-media-irreplaceable.service" ];
  systemd.services.restic-backups-open-webui.unitConfig.OnFailure =
    [ "notify@restic-backups-open-webui.service" ];

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
      repository = "/var/backup/restic-local/open-webui";
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
  };
}
