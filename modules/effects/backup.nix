{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
    mkIf
    ;
in
{
  # nori.backups + nori.backupTargets — declarative restic backup model.
  #
  # Two-layer schema:
  #
  #   nori.backupTargets.<target>  — WHERE backups go (the destination
  #                                  repo bases). Declared once at
  #                                  host scope.
  #   nori.backups.<job>           — WHAT to back up (paths, prepare
  #                                  commands, retention). Declared per
  #                                  service module alongside the
  #                                  service definition.
  #
  # The generator fans out: each (job, target) pair becomes its own
  # `services.restic.backups.<job>-<target>` and corresponding
  # `restic-backups-<job>-<target>.service` systemd unit with its own
  # OnFailure → notify@ wiring. That's deliberate — independent units
  # mean independent failure modes. A wedged OneTouch USB controller
  # (2026-06-04 incident) doesn't take down the ironwolf-local backups,
  # and ntfy alerts disambiguate which target failed.
  #
  # Service modules look like:
  #
  #   nori.backups.sonarr = { include = [ "/var/lib/sonarr" ]; };
  #
  #   nori.backups.vaultwarden = {
  #     include = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
  #     prepareCommand = ''
  #       ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
  #         ".backup '/var/backup/vaultwarden/db.sqlite3'"
  #     '';
  #   };
  #
  # By default every job writes to every declared target. Override
  # selectively via `targets = [ "onetouch" ];` per job.
  #
  # Three pattern shapes from docs/SERVICES.md § "Backup-correctness
  # patterns" fit this schema:
  #   * Pattern A (filesystem-only)   → include = [...];
  #   * Pattern B (built-in dump)     → include lists the dump dir
  #   * Pattern C2 (external dump)    → include + prepareCommand
  #
  # DynamicUser services: point `include` at /var/lib/private/<n>,
  # not /var/lib/<n> (which is a symlink restic would store as a
  # symlink → 0-byte snapshot). Enforced by the `badPaths` assertion
  # below; see .claude/skills/gotcha-dynamicuser-statedirectory-symlink/

  options.nori.backupTargets = mkOption {
    default = { };
    description = ''
      Available restic backup destinations. Each target provides a
      `repository` URL or path prefix under which per-job repos will
      live; the generated repo for a job named `vaultwarden` against
      a target with `repository = "/mnt/backup"` is
      `/mnt/backup/vaultwarden`. Remote URLs concatenate identically:
      `repository = "sftp:restic@aurora.saola-matrix.ts.net:/mnt/backup"`
      yields `sftp:restic@aurora.saola-matrix.ts.net:/mnt/backup/vaultwarden`.

      Targets are independent — every backup job fans out to every
      target it lists by default, and each (job, target) pair gets its
      own systemd unit + OnFailure notify@ wiring. A failed target
      doesn't block other targets.

      Declared once at host scope (typically in
      modules/services/backup/restic.nix).
    '';
    example = lib.literalExpression ''
      {
        onetouch = {
          repository = "/mnt/backup";
          description = "USB OneTouch external HDD (lazy-mounted via autofs)";
        };
        onetouch-remote = {
          repository = "sftp:restic@aurora.saola-matrix.ts.net:/mnt/backup";
          description = "Same OneTouch HDD relocated to aurora; off-host vault";
          extraOptions = [
            "sftp.command='ssh -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
          ];
        };
        hetzner = {
          repository = "sftp:u123456@u123456.your-storagebox.de:23/restic";
          description = "Hetzner Storage Box, off-site";
          extraOptions = [
            "sftp.command='ssh -i /run/secrets/restic-hetzner-key -p 23 u123456@u123456.your-storagebox.de -s sftp'"
          ];
        };
      }
    '';
    type = types.attrsOf (
      types.submodule {
        options = {
          repository = mkOption {
            type = types.str;
            example = "sftp:restic@aurora.saola-matrix.ts.net:/mnt/backup";
            description = ''
              Restic repository spec. Per-job repos derive as
              `<repository>/<jobName>` — slash-concat works
              identically for local paths and remote URLs. Any
              restic-supported backend is valid:

                local path  `/mnt/backup`
                SFTP        `sftp:user@host:/abs/path`
                REST        `rest:https://server:port/`
                S3          `s3:s3.amazonaws.com/bucket`
                B2          `b2:bucketname:path`

              For backends that need transport config (SSH identity,
              alternate known_hosts) use `extraOptions`. For backends
              that need ambient credentials (AWS_ACCESS_KEY_ID,
              B2_ACCOUNT_ID, …) use `environmentFile`.

              Local paths must exist (or be mountable) at backup
              time; restic's `initialize = true` will create the
              per-job subdirectory and init the repo on first run.
              Remote repositories must already be reachable — restic
              will not create the remote root.
            '';
          };
          description = mkOption {
            type = types.str;
            description = "One-line human-readable description; surfaces in commit messages and runbooks.";
          };
          extraOptions = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [
              "sftp.command='ssh -i /run/secrets/restic-ssh-key -o UserKnownHostsFile=/run/secrets/restic-known-hosts restic@aurora.saola-matrix.ts.net -s sftp'"
            ];
            description = ''
              Extra `-o <opt>` flags passed to every restic invocation
              against this target. Most commonly used for SFTP to
              point at a non-default SSH identity file or known_hosts.
            '';
          };
          environmentFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            example = "/run/secrets/restic-hetzner-env";
            description = ''
              Path to an env file (typically sops-decrypted under
              /run/secrets/) holding credentials like
              AWS_ACCESS_KEY_ID, B2_ACCOUNT_ID, etc. Sourced into the
              restic unit's environment at startup. Null for local
              paths and for SFTP-by-key (key path goes in
              `extraOptions`).
            '';
          };
        };
      }
    );
  };

  options.nori.backups = mkOption {
    default = { };
    description = ''
      Restic backup decisions per service / cross-cutting concern.

      Each entry MUST set exactly one of:
        * `include` — list of paths to back up (Pattern A; add
          `prepareCommand` for Pattern C2)
        * `skip` — string explaining why this service has no backup
          (covered elsewhere, stateless, intentionally re-derivable)

      The two-state schema forces every service module to make an
      explicit decision rather than silently being uncovered. The
      paired flake check (`every-service-has-backup-intent` in
      flake.nix) enforces that every modules/server/**.nix
      contains a nori.backups.<n> declaration.

      Active backups (those with non-null `include`) fan out across
      all `targets` listed (default: every declared
      nori.backupTargets entry). The generated systemd unit names
      follow `restic-backups-<jobName>-<targetName>`.
    '';
    example = lib.literalExpression ''
      {
        sonarr = { include = [ "/var/lib/sonarr" ]; };
        vaultwarden = {
          include = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
          prepareCommand = "sqlite3 ... .backup ...";
          timer = "*-*-* 04:30:00";
          # targets defaults to all declared nori.backupTargets;
          # override here to limit, e.g.:
          # targets = [ "onetouch" ];
        };
        gatus = { skip = "memory-only storage; no on-disk state."; };
      }
    '';
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            include = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = ''
                Filesystem paths to back up. Passed through to
                restic's positional arguments (the restic NixOS
                module's `paths` option). For DynamicUser services,
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
                When `include` is null, this records why backup is
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
                `include` is null. Same prepareCommand runs once per
                target; the dump output it produces gets included in
                every target's snapshot.
              '';
            };
            exclude = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "/var/lib/qBittorrent/qBittorrent/incomplete" ];
              description = ''
                Paths to exclude from the backup. Mirrors restic's
                `--exclude`. Use for ephemeral subdirs under a
                service's state path that re-fill from scratch (qBit
                `incomplete/`, browser caches, etc.) — pinning their
                chunks in old snapshots costs real bytes on the backup
                drive. Ignored when `include` is null.
              '';
            };
            timer = mkOption {
              type = types.str;
              default = "*-*-* 03:00:00";
              description = ''
                `OnCalendar` systemd timer expression. Default 03:00
                UTC daily. All targets for a job share the same timer;
                they fire concurrently. Stagger across jobs when
                concurrent USB I/O on the OneTouch becomes a
                bottleneck. Ignored when `include` is null.
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
                Value tier per docs/STORAGE.md "Value tiers" — drives
                the default `pruneOpts` retention curve (see
                `pruneOpts` defaultText below). Per-service repos
                default to `service`; cross-cutting `user-data` and
                `media-irreplaceable` repos override. Override
                `pruneOpts` directly to deviate.
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
              description = "Restic forget/prune options. Default derived from `tier`. Ignored when `include` is null.";
            };
            targets = mkOption {
              type = types.nullOr (types.listOf types.str);
              # Default = every declared nori.backupTargets entry. The
              # default is read from the outer `config` argument because
              # this submodule can't see the parent without `mkOptionDefault`
              # gymnastics; the actual resolution happens in the generator
              # below.
              default = null;
              defaultText = lib.literalExpression "lib.attrNames config.nori.backupTargets";
              description = ''
                Backup targets this job should fan out to. Default
                (null) = every declared nori.backupTargets entry —
                belt-and-suspenders coverage. Override with a subset
                when a job should NOT write to a particular target
                (e.g. a service whose data is too large for the
                always-mounted target).
              '';
            };
          };
        }
      )
    );
  };

  config = mkIf (config.nori.backups != { }) (
    let
      # Default targets to all declared destinations if a job didn't
      # specify them — done here rather than in the submodule default
      # so each entry sees the full top-level `nori.backupTargets`.
      effectiveTargets =
        cfg: if cfg.targets == null then lib.attrNames config.nori.backupTargets else cfg.targets;

      activeJobs = lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups;

      # Flattened (jobName, target, cfg) triples — the cartesian
      # product of jobs × their targets. Used by both the
      # services.restic.backups generator and the OnFailure wiring.
      activePairs = lib.flatten (
        lib.mapAttrsToList (
          jobName: cfg:
          map (target: {
            inherit jobName cfg target;
          }) (effectiveTargets cfg)
        ) activeJobs
      );

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
          if cfg.include == null then
            [ ]
          else
            lib.filter (p: lib.any (svc: p == "/var/lib/${svc}") dynamicUserServices) cfg.include
        ) config.nori.backups
      );

      # Host-aware placement check — appliance and agent both reject
      # path-based backups, for different reasons (anti-write storage
      # vs intentional impermanence; see role enum in hosts.nix). The
      # structural fix for appliance is the planned local SSD — see
      # modules/server/backup/restic.nix L28.
      myRole = config.nori.hosts.${config.networking.hostName}.role or null;
      backupPaths = lib.filter (cfg: cfg.include != null) (lib.attrValues config.nori.backups);

      # Validate that every per-job `targets` references a real
      # declared target. Catches typos at eval time rather than at
      # daily-3am restic failure time.
      unknownTargets = lib.flatten (
        lib.mapAttrsToList (
          jobName: cfg:
          if cfg.include == null then
            [ ]
          else
            map (t: "${jobName} → ${t}") (
              lib.filter (t: !(builtins.hasAttr t config.nori.backupTargets)) (effectiveTargets cfg)
            )
        ) config.nori.backups
      );
    in
    {
      assertions = [
        {
          assertion = lib.all (cfg: (cfg.include != null) != (cfg.skip != null)) (
            lib.attrValues config.nori.backups
          );
          message = ''
            Each nori.backups.<n> entry must set exactly one of `include`
            (with content to back up) or `skip` (with a reason string),
            never both and never neither. Forgetting to make the
            decision is exactly the silent-coverage-gap this schema
            shape exists to prevent.
          '';
        }
        {
          assertion = badPaths == [ ];
          message = ''
            nori.backups include entries reference DynamicUser symlinks.
            restic stores symlinks AS symlinks; pointing at /var/lib/<n>
            for a DynamicUser service produces a 0-byte snapshot. Use
            /var/lib/private/<n> for these paths instead.

            Offending paths: ${lib.concatStringsSep ", " badPaths}

            Known DynamicUser services: ${lib.concatStringsSep ", " dynamicUserServices}
            See .claude/skills/gotcha-dynamicuser-statedirectory-symlink/
            for the full story.
          '';
        }
        {
          assertion = myRole != "appliance" || backupPaths == [ ];
          message = ''
            Host ${config.networking.hostName} has nori.hosts.<self>.role = "appliance".
            Appliance hosts have anti-write storage (no swap, volatile
            journald, flash-only — see hosts/${config.networking.hostName}/hardware.nix)
            and no local restic target. All nori.backups.<n> declarations
            on appliance hosts must use `skip = "<reason>"`, not `include`.

            Offending: ${
              lib.concatStringsSep ", " (
                lib.attrNames (lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups)
              )
            }

            If you need to back up data that legitimately lives on this
            host, the structural fix is the planned local-fast-restore
            disk (see modules/server/backup/restic.nix L28). Until that
            lands, declare `skip = "..."` and document the rationale.
          '';
        }
        {
          assertion = myRole != "agent" || backupPaths == [ ];
          message = ''
            Host ${config.networking.hostName} has nori.hosts.<self>.role = "agent".
            Agent hosts are designed to be wiped every boot (root on
            tmpfs via impermanence; only /persist survives — see
            machines/${config.networking.hostName}/default.nix). Local
            state is intentionally ephemeral; restic-ing it would
            contradict the entire posture. All nori.backups.<n>
            declarations on agent hosts must use `skip = "<reason>"`,
            not `include`.

            Offending: ${
              lib.concatStringsSep ", " (
                lib.attrNames (lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups)
              )
            }

            If there's data that legitimately needs to outlive a
            reboot, add it to environment.persistence."/persist" in
            this host's default.nix — that's the agent-host equivalent
            of "back this up." If it doesn't need to survive, leave it
            ephemeral (the desired state for anything an agent
            generates).
          '';
        }
        {
          assertion = unknownTargets == [ ];
          message = ''
            nori.backups.<job>.targets references a backup target that
            isn't declared in nori.backupTargets.

            Offending pairs: ${lib.concatStringsSep ", " unknownTargets}

            Declared targets: ${lib.concatStringsSep ", " (lib.attrNames config.nori.backupTargets)}

            Either declare the missing target (top-level
            `nori.backupTargets.<name> = { repository = ...; description = ...; }`)
            or fix the typo on the offending job.
          '';
        }
        {
          # No-targets vacuously satisfies the cartesian product but
          # silently produces zero backup units, which would let a
          # service slip through `every-service-has-backup-intent`
          # without any actual backup running. Flag it.
          assertion = activeJobs == { } || config.nori.backupTargets != { };
          message = ''
            nori.backups has active jobs (with non-null `include`) but
            nori.backupTargets is empty — no targets means no restic
            units get generated. Declare at least one target in
            modules/server/backup/restic.nix (or override per-host).
          '';
        }
      ];

      services.restic.backups = lib.listToAttrs (
        map (
          {
            jobName,
            cfg,
            target,
          }:
          let
            tgt = config.nori.backupTargets.${target};
          in
          lib.nameValuePair "${jobName}-${target}" {
            paths = cfg.include;
            inherit (cfg) exclude;
            repository = "${tgt.repository}/${jobName}";
            passwordFile = config.sops.secrets.restic-password.path;
            initialize = true;
            backupPrepareCommand = cfg.prepareCommand;
            timerConfig = {
              OnCalendar = cfg.timer;
              Persistent = true;
            };
            inherit (cfg) pruneOpts;
            inherit (tgt) extraOptions environmentFile;
          }
        ) activePairs
      );

      # Auto-generated OnFailure → notify@ wiring per (job, target).
      # Mirror of the manual block this replaced in
      # modules/server/backup/restic.nix; without it a silent backup
      # failure stays silent. Per-target means the ntfy message names
      # exactly which target failed.
      systemd.services = lib.listToAttrs (
        map (
          { jobName, target, ... }:
          lib.nameValuePair "restic-backups-${jobName}-${target}" {
            unitConfig.OnFailure = [ "notify@restic-backups-${jobName}-${target}.service" ];
          }
        ) activePairs
      );
    }
  );
}
