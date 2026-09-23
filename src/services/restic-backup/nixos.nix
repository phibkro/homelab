{
  config,
  lib,
  pkgs,
  ...
}:

let
  backup = config.nori.inventory.backup;
  remoteBackup = config.networking.hostName == "adelie";
  userDataPaths = lib.mapAttrsToList (_: f: f.path) (
    lib.filterAttrs (_: f: f.tier == "user") config.nori.fs
  );
  irreplaceablePaths = lib.mapAttrsToList (_: f: f.path) (
    lib.filterAttrs (_: f: f.tier == "irreplaceable") config.nori.fs
  );
  remote = backup.adelie;
  remoteKnownHosts = pkgs.writeText "adelie-backup-known-hosts" ''
    ${backup.hostname} ${remote.hostKey}
  '';
  /*
    Shared (job, target) iteration for the weekly + monthly check
    scripts. Each check carries the target's `extraOptions` and
    `environmentFile` alongside the repository path, so verification
    uses the same transport and credentials as the backup unit.
  */
  activeJobs = lib.optionalAttrs backup.enabled (
    lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups
  );
  activePairs = lib.flatten (
    lib.mapAttrsToList (
      jobName: cfg:
      let
        targets = if cfg.targets == null then lib.attrNames config.nori.backupTargets else cfg.targets;
      in
      map (target: {
        inherit jobName target;
        tgt = config.nori.backupTargets.${target};
      }) targets
    ) activeJobs
  );

  /*
    `checkArgs` are the per-cadence `restic check` flags (none weekly,
    --read-data-subset monthly). Failures accumulate rather than
    short-circuit so a corrupt repo can't hide rot in the others.

    Target `extraOptions` are interpolated RAW, matching the generated
    backup units' command-line parsing. One inline restic call per pair
    keeps check invocations identical to the corresponding backup.
  */
  mkCheckScript =
    checkArgs:
    let
      flags = lib.concatStringsSep " " checkArgs;
      pairCall =
        {
          jobName,
          target,
          tgt,
        }:
        let
          repo = "${tgt.repository}/${jobName}";
          extraOpts = lib.concatMapStringsSep " " (o: "-o ${o}") tgt.extraOptions;
          # environmentFile sourced inside the per-pair subshell so one
          # target's credentials never leak into the next invocation.
          envPrefix = lib.optionalString (
            tgt.environmentFile != null
          ) "set -a; . ${lib.escapeShellArg (toString tgt.environmentFile)}; set +a; ";
        in
        ''
          echo ${lib.escapeShellArg "[${jobName} @ ${target}] restic check ${flags} (${repo})"}
          if (
            # Self-heal a stale exclusive lock left by a prior aborted check
            # (a reboot mid-run, an OOM). `restic unlock` only removes locks
            # older than 30min, so a concurrent run is untouched. Same rationale
            # as the backup units' pre-unlock — but INSIDE the check so it's
            # structural, not a separate ExecStartPre that could drift.
            ${envPrefix}${pkgs.restic}/bin/restic ${extraOpts} -r ${lib.escapeShellArg repo} unlock >/dev/null 2>&1 || true
            ${pkgs.restic}/bin/restic ${extraOpts} -r ${lib.escapeShellArg repo} check ${flags}
          ); then
            :
          else
            echo ${lib.escapeShellArg "[${jobName} @ ${target}] FAILED"}
            fail=1
          fi
        '';
    in
    ''
      fail=0
      ${lib.concatMapStringsSep "\n" pairCall activePairs}
      exit $fail
    '';
in
/*
  Reusable restic sender composition for explicitly enabled backup policies.
  The workstation imports it without activating it while backup.enabled is
  false. Test fixtures select their own mounted destination and credentials.
*/
{
  imports = [
    { nori.backupDelivery.enable = backup.enabled; }
    {
      config = lib.mkIf (backup.enabled && !remoteBackup) {
        systemd.services = lib.listToAttrs (
          map
            (
              name:
              lib.nameValuePair name {
                unitConfig = {
                  RequiresMountsFor = [ backup.mountPoint ];
                  AssertPathIsMountPoint = backup.mountPoint;
                };
              }
            )
            (
              [
                "restic-check-weekly"
                "restic-check-monthly"
              ]
              ++ map (pair: "restic-backups-${pair.jobName}-${pair.target}") activePairs
            )
        );
      };
    }
  ];

  config = lib.mkIf backup.enabled {
    /**
      Cross-cutting restic infrastructure: the shared password secret,
      the /var/backup tmpfiles rule that Pattern C2 prepareCommands
      write into, the backup target declarations, and the weekly +
      monthly verification timers that iterate over every repo declared
      via `nori.backups`.

      Per-job declarations live in the service modules they belong
      to (`nori.backups.sonarr` in sonarr.nix, etc.) — see
      src/infra/common/nixos/backup.nix for the abstraction. The non-service-tied
      jobs (user-data for /home + /srv/share, family-irreplaceable for
      /mnt/family subvolumes + Immich's Pattern B dump dir) are declared
      at the bottom of this file because they do not belong to one service.

      Every job fans out to each declared target by default. Each
      (job, target) becomes an independent systemd unit with its own
      failure notification.

      The inventory declares the target filesystem. It remains inactive until
      the backup policy is explicitly enabled after disk identity verification.
    */

    sops.secrets = {
      restic-password = {
        owner = "root";
        mode = "0400";
      };
    }
    // lib.optionalAttrs remoteBackup {
      restic-ssh-key = {
        owner = "root";
        mode = "0400";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/backup 0755 root root -"
    ];

    nori.backupTargets.${backup.targetName} =
      if remoteBackup then
        {
          repository = "sftp:${remote.user}@${backup.hostname}:/${remote.repositoryPrefix}";
          description = "Restricted Adelie namespace on workstation-attached ${backup.targetName}.";
          tailnetPeer = backup.hostname;
          extraOptions = [
            "sftp.command='ssh -i ${config.sops.secrets.restic-ssh-key.path} -o IdentitiesOnly=yes -o UserKnownHostsFile=${remoteKnownHosts} ${remote.user}@${backup.hostname} -s sftp'"
          ];
        }
      else
        {
          repository = backup.mountPoint;
          description = "Locally attached ${backup.targetName} backup filesystem.";
        };

    # Refuse backup/check execution when the dedicated filesystem is absent.
    # RequiresMountsFor starts it; AssertPathIsMountPoint also rejects fallback
    # to a plain directory on the root filesystem.

    /**
      ---------------------------------------------------------------------
      Backup verification cadence (STORAGE.md § "Backup verification").

      Two timers in addition to the daily backup runs:
        weekly  — `restic check`               (metadata only, fast)
        monthly — `restic check --read-data-subset=10%`
                  (samples 10% of pack data; covers 100% over ~10 months)

      Both iterate every (job, target) pair derived from `nori.backups`
      and `nori.backupTargets`. Either step failing for any pair trips
      OnFailure → notify@ → ntfy.sh urgent alert. A backup that
      succeeds-but-rots silently is the failure mode this guards against.

      The wrapper iterates serially (USB HDD; concurrent reads thrash).
      Failures don't short-circuit — every repo gets attempted so a
      corrupt repo doesn't hide rot in the others. A pair failure
      against an offline target (e.g. OneTouch USB unplugged) is also
      a real signal, not just noise — restic will report
      "no such file or directory" / "no such device" and the ntfy
      alert names which target.
    */
    systemd.services.restic-check-weekly = {
      description = "Weekly metadata check of all restic repositories";
      unitConfig.OnFailure = [ "notify@restic-check-weekly.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = mkCheckScript [ ];
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
      unitConfig.OnFailure = [ "notify@restic-check-monthly.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = mkCheckScript [ "--read-data-subset=10%" ];
    };

    systemd.timers.restic-check-monthly = {
      description = "Monthly read-10% data sample check of all restic repositories";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-01 06:00:00"; # 1st of each month
        Persistent = true;
      };
    };

    /*
      Non-service-tied backup repos. Paths derived from nori.fs tier —
      adding a new subvol in disko-media.nix with `tier = "irreplaceable"`
      flows through to media-irreplaceable.include automatically; same for
      `user` → user-data.include.
    */

    nori.backups.user-data = lib.mkIf (!remoteBackup && userDataPaths != [ ]) {
      include = userDataPaths;
      # Preserve harness history, sessions, plans, databases, and credentials,
      # but do not pin large reproducible caches into retained snapshots. OMP is
      # intentionally absent until its on-disk cache layout is observed after
      # installation; ~/.omp is otherwise covered by the /home snapshot.
      exclude = [
        "/home/nori/.codex/.tmp"
        "/home/nori/.codex/cache"
        "/home/nori/.codex/ipc"
        "/home/nori/.codex/logs_2.sqlite"
        "/home/nori/.codex/logs_2.sqlite-shm"
        "/home/nori/.codex/logs_2.sqlite-wal"
        "/home/nori/.codex/mcp-oauth-locks"
        "/home/nori/.codex/models_cache.json"
        "/home/nori/.codex/shell_snapshots"
        "/home/nori/.codex/vendor_imports"
        "/home/nori/.claude/backups"
        "/home/nori/.claude/cache"
        "/home/nori/.claude/daemon"
        "/home/nori/.claude/paste-cache"
        "/home/nori/.claude/plugins/cache"
        "/home/nori/.claude/remote"
        "/home/nori/.claude/shell-snapshots"
      ];
      restoreSamples = [
        "/home/nori/.ssh/config"
        "/srv/nori/Documents/abstract_algebra.pdf"
        "/srv/share/projects/homelab/flake.lock"
      ];
      tier = "user";
      timer = "*-*-* 03:00:00";
    };

    /*
      Immich stores its scheduled SQL dumps under mediaLocation/backups,
      inside the photos tree already selected by the irreplaceable tier.
      Include that tree once; a separate historical state-directory path
      would make restic fail when the old directory no longer exists.

      The enabled destination receives this repository. Verify available capacity
      and source readability before the first full run.
    */
    nori.backups.media-irreplaceable = lib.mkIf (!remoteBackup && irreplaceablePaths != [ ]) {
      include = irreplaceablePaths;
      tier = "irreplaceable";
      /*
        Cold canonical media changes slowly. Keep a week's daily recovery,
        then sparse independent history; restic deduplicates unchanged content
        across snapshots. This intentionally narrows the generic
        irreplaceable default (14d / 8w / 12m / 5y), which suits frequently
        changing service state rather than a capacity-constrained HDD archive.
      */
      pruneOpts = backup.retention.coldMedia.resticPruneOpts;
      timer = "*-*-* 03:30:00";
      targets = [ backup.targetName ];
    };
  };
}
