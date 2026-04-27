{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrs'
    nameValuePair
    ;
in
{
  # nori.backups — single source of truth for restic backup repos.
  # Each entry generates ALL of:
  #   * services.restic.backups.<name>        (the backup job)
  #   * systemd OnFailure → notify@ wiring    (ntfy alert on failure)
  #   * inclusion in the weekly + monthly     (verification cadence)
  #     restic check loops in backup-restic.nix
  #
  # Service modules declare their own backup inline alongside the
  # service definition, the same way they declare lanRoutes:
  #
  #   nori.backups.sonarr = { paths = [ "/var/lib/sonarr" ]; };
  #
  #   nori.backups.vaultwarden = {
  #     paths = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
  #     prepareCommand = ''
  #       ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
  #         ".backup '/var/backup/vaultwarden/db.sqlite3'"
  #     '';
  #   };
  #
  # Three pattern shapes from DESIGN.md L210-289 fit this schema:
  #   * Pattern A (filesystem-only)   → paths = [...];
  #   * Pattern B (built-in dump)     → paths includes the dump dir
  #   * Pattern C2 (external dump)    → paths + prepareCommand
  #
  # ── DynamicUser symlink gotcha ──────────────────────────────────
  # Services declared with `DynamicUser = true` (open-webui,
  # jellyseerr, prowlarr, ntfy-sh, beszel-hub, gatus, glance, ollama)
  # have their state at /var/lib/private/<name> with a SYMLINK at
  # /var/lib/<name>. restic stores symlinks AS symlinks; pointing
  # backups at /var/lib/<name> produces a 0-byte snapshot of just
  # the symlink record, not the data. For these services, declare
  # paths against /var/lib/private/<name> directly. See
  # docs/gotchas.md.

  options.nori.backups = mkOption {
    default = { };
    description = ''
      Restic backup jobs. Attribute name = repo name (becomes
      `/mnt/backup/<name>`); value declares paths + optional
      pre-backup command + timer/retention overrides.
    '';
    example = lib.literalExpression ''
      {
        sonarr = { paths = [ "/var/lib/sonarr" ]; };
        vaultwarden = {
          paths = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
          prepareCommand = "sqlite3 ... .backup ...";
          timer = "*-*-* 04:30:00";
        };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          paths = mkOption {
            type = types.listOf types.str;
            description = ''
              Filesystem paths to back up. For DynamicUser services,
              point at /var/lib/private/<name> directly — the
              /var/lib/<name> symlink would otherwise be stored as
              just the symlink record.
            '';
          };
          prepareCommand = mkOption {
            type = types.nullOr types.lines;
            default = null;
            description = ''
              Bash command(s) to run before each restic backup.
              Used for Pattern C2 (sqlite3 .backup before restic).
              Null = Pattern A (filesystem-only).
            '';
          };
          timer = mkOption {
            type = types.str;
            default = "*-*-* 03:00:00";
            description = ''
              `OnCalendar` systemd timer expression. Default 03:00
              UTC daily. Stagger across repos when concurrent USB
              I/O on the OneTouch becomes a bottleneck.
            '';
          };
          pruneOpts = mkOption {
            type = types.listOf types.str;
            default = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 12"
            ];
            description = "Restic forget/prune options.";
          };
        };
      }
    );
  };

  config = mkIf (config.nori.backups != { }) {
    services.restic.backups = mapAttrs' (
      name: cfg:
      nameValuePair name {
        inherit (cfg) paths;
        repository = "/mnt/backup/${name}";
        passwordFile = config.sops.secrets.restic-password.path;
        initialize = true;
        backupPrepareCommand = cfg.prepareCommand;
        timerConfig = {
          OnCalendar = cfg.timer;
          Persistent = true;
        };
        inherit (cfg) pruneOpts;
      }
    ) config.nori.backups;

    # Auto-generated OnFailure → notify@ wiring per repo. Mirror of
    # the manual block this replaced in backup-restic.nix; without
    # it a silent backup failure stays silent.
    systemd.services = mapAttrs' (
      name: _:
      nameValuePair "restic-backups-${name}" {
        unitConfig.OnFailure = [ "notify@restic-backups-${name}.service" ];
      }
    ) config.nori.backups;
  };
}
