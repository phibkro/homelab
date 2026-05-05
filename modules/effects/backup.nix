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
  #     restic check loops in modules/server/backup/restic.nix
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
      Restic backup decisions. Attribute name = repo name (becomes
      `/mnt/backup/<name>`).

      Each entry MUST set exactly one of:
        * `paths` — list of paths to back up (Pattern A; add
          `prepareCommand` for Pattern C2)
        * `skip` — string explaining why this service has no backup
          (covered elsewhere, stateless, intentionally re-derivable)

      The two-state schema forces every service module to make an
      explicit decision rather than silently being uncovered. The
      paired flake check (`every-service-has-backup-intent` in
      flake.nix) enforces that every modules/server/**.nix
      contains a nori.backups.<n> declaration.
    '';
    example = lib.literalExpression ''
      {
        sonarr = { paths = [ "/var/lib/sonarr" ]; };
        vaultwarden = {
          paths = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
          prepareCommand = "sqlite3 ... .backup ...";
          timer = "*-*-* 04:30:00";
        };
        gatus = { skip = "memory-only storage; no on-disk state."; };
      }
    '';
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            paths = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = ''
                Filesystem paths to back up. For DynamicUser services,
                point at /var/lib/private/<name> directly — the
                /var/lib/<name> symlink would otherwise be stored as
                just the symlink record (caught by the assertion
                below). Set to `null` (default) for explicit opt-out;
                pair with the `skip` field documenting the reason.
              '';
            };
            skip = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                When `paths` is null, this records why backup is
                intentionally skipped. Required for opt-out — the
                schema can't otherwise tell "intentionally skipped"
                from "forgotten".
              '';
            };
            prepareCommand = mkOption {
              type = types.nullOr types.lines;
              default = null;
              description = ''
                Bash command(s) to run before each restic backup.
                Used for Pattern C2 (sqlite3 .backup before restic).
                Null = Pattern A (filesystem-only). Ignored when
                `paths` is null.
              '';
            };
            timer = mkOption {
              type = types.str;
              default = "*-*-* 03:00:00";
              description = ''
                `OnCalendar` systemd timer expression. Default 03:00
                UTC daily. Stagger across repos when concurrent USB
                I/O on the OneTouch becomes a bottleneck. Ignored
                when `paths` is null.
              '';
            };
            tier = mkOption {
              type = types.enum [
                "service"
                "user"
                "irreplaceable"
              ];
              default = "service";
              description = ''
                Value tier — drives the default `pruneOpts` retention
                curve. Mirrors the docs/DESIGN.md "Three value tiers"
                framing. Per-service repos default to `service`; the
                cross-cutting `user-data` and `media-irreplaceable`
                repos override.

                * `service`       — short retention (7d / 4w / 12m).
                                    Service state is mostly re-buildable
                                    if the latest snapshot is healthy.
                * `user`          — medium retention (14d / 4w / 12m).
                                    User-touched data is harder to
                                    re-derive than service state.
                * `irreplaceable` — long retention (14d / 8w / 12m / 5y).
                                    Photos / home-videos / projects —
                                    the data the lab exists for.

                Override `pruneOpts` directly to deviate from the
                tier's default curve.
              '';
            };
            pruneOpts = mkOption {
              type = types.listOf types.str;
              default =
                {
                  service = [
                    "--keep-daily 7"
                    "--keep-weekly 4"
                    "--keep-monthly 12"
                  ];
                  user = [
                    "--keep-daily 14"
                    "--keep-weekly 4"
                    "--keep-monthly 12"
                  ];
                  irreplaceable = [
                    "--keep-daily 14"
                    "--keep-weekly 8"
                    "--keep-monthly 12"
                    "--keep-yearly 5"
                  ];
                }
                .${config.tier};
              defaultText = lib.literalExpression ''
                # derived from `tier`:
                # service       → 7d / 4w / 12m
                # user          → 14d / 4w / 12m
                # irreplaceable → 14d / 8w / 12m / 5y
              '';
              description = "Restic forget/prune options. Default derived from `tier`. Ignored when `paths` is null.";
            };
          };
        }
      )
    );
  };

  config = mkIf (config.nori.backups != { }) (
    let
      activeBackups = lib.filterAttrs (_: cfg: cfg.paths != null) config.nori.backups;

      # Services that use systemd DynamicUser=yes plus StateDirectory,
      # where /var/lib/<n> is a SYMLINK to /var/lib/private/<n>. restic
      # stores symlinks as symlinks; a backup pointing at /var/lib/<n>
      # for one of these services produces an empty (3-file / 0-byte)
      # snapshot. Derived from systemd unit configs — assertions run
      # after the module fixed-point so config.systemd.services is
      # fully resolved. Self-maintaining: a new DynamicUser service
      # appears here automatically the moment its module enables it.
      dynamicUserServices = lib.attrNames (
        lib.filterAttrs (_: cfg: cfg.serviceConfig.DynamicUser or false) config.systemd.services
      );

      badPaths = lib.flatten (
        lib.mapAttrsToList (
          _: cfg:
          if cfg.paths == null then
            [ ]
          else
            lib.filter (p: lib.any (svc: p == "/var/lib/${svc}") dynamicUserServices) cfg.paths
        ) config.nori.backups
      );

      # Host-aware placement check. Reads the role tag from the
      # nori.hosts registry (modules/effects/hosts.nix). Appliance hosts
      # have anti-write storage (no swap, volatile journald, flash-
      # only — see hosts/pi/hardware.nix) so daily restic to local
      # disk contradicts the storage philosophy. The structural answer
      # (push backups to a real disk that lives on the appliance) is
      # planned but deferred — see modules/server/backup/restic.nix
      # L28 "pi (local fast restore, when the SSD lands)". Until
      # then, every nori.backups.<n> on an appliance host MUST use
      # `skip = "..."`.
      myRole = config.nori.hosts.${config.networking.hostName}.role or null;
      appliancePaths = lib.filter (cfg: cfg.paths != null) (lib.attrValues config.nori.backups);
    in
    {
      assertions = [
        {
          assertion = lib.all (cfg: (cfg.paths != null) != (cfg.skip != null)) (
            lib.attrValues config.nori.backups
          );
          message = ''
            Each nori.backups.<n> entry must set exactly one of `paths`
            (with content to back up) or `skip` (with a reason string),
            never both and never neither. Forgetting to make the
            decision is exactly the silent-coverage-gap this schema
            shape exists to prevent.
          '';
        }
        {
          assertion = badPaths == [ ];
          message = ''
            nori.backups paths reference DynamicUser symlinks. restic
            stores symlinks AS symlinks; pointing at /var/lib/<n> for
            a DynamicUser service produces a 0-byte snapshot. Use
            /var/lib/private/<n> for these paths instead.

            Offending paths: ${lib.concatStringsSep ", " badPaths}

            Known DynamicUser services: ${lib.concatStringsSep ", " dynamicUserServices}
            See docs/gotchas.md "DynamicUser StateDirectory" for the
            full story.
          '';
        }
        {
          assertion = myRole != "appliance" || appliancePaths == [ ];
          message = ''
            Host ${config.networking.hostName} has nori.hosts.<self>.role = "appliance".
            Appliance hosts have anti-write storage (no swap, volatile
            journald, flash-only — see hosts/${config.networking.hostName}/hardware.nix)
            and no local restic target. All nori.backups.<n> declarations
            on appliance hosts must use `skip = "<reason>"`, not `paths`.

            Offending: ${
              lib.concatStringsSep ", " (
                lib.attrNames (lib.filterAttrs (_: cfg: cfg.paths != null) config.nori.backups)
              )
            }

            If you need to back up data that legitimately lives on this
            host, the structural fix is the planned local-fast-restore
            disk (see modules/server/backup/restic.nix L28). Until that
            lands, declare `skip = "..."` and document the rationale.
          '';
        }
      ];

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
      ) activeBackups;

      # Auto-generated OnFailure → notify@ wiring per repo. Mirror
      # of the manual block this replaced in modules/server/backup/restic.nix;
      # without it a silent backup failure stays silent.
      systemd.services = mapAttrs' (
        name: _:
        nameValuePair "restic-backups-${name}" {
          unitConfig.OnFailure = [ "notify@restic-backups-${name}.service" ];
        }
      ) activeBackups;
    }
  );
}
