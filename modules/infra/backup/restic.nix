{
  config,
  lib,
  pkgs,
  ...
}:

let
  /*
    Shared (job, target) iteration for the weekly + monthly check
    scripts. Each check carries the target's `extraOptions` and
    `environmentFile` alongside the repository path, so verification
    uses the same transport and credentials as the backup unit.
  */
  activeJobs = lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups;
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
  Selected only by the Workstation `backup-source` system profile. The
  cross-cutting targets, user-data + media-irreplaceable jobs, and check
  timers belong there because Workstation owns the relevant source data.
*/
{
  /**
    Cross-cutting restic infrastructure: the shared password secret,
    the /var/backup tmpfiles rule that Pattern C2 prepareCommands
    write into, the backup target declarations, and the weekly +
    monthly verification timers that iterate over every repo declared
    via `nori.backups`.

    Per-job declarations live in the service modules they belong
    to (`nori.backups.sonarr` in sonarr.nix, etc.) — see
    modules/infra/backup/default.nix for the abstraction. The non-service-tied
    jobs (user-data for /home + /srv/share, family-irreplaceable for
    /mnt/family subvolumes + Immich's Pattern B dump dir) are declared
    at the bottom of this file because they do not belong to one service.

    Every job fans out to each declared target by default. Each
    (job, target) becomes an independent systemd unit with its own
    failure notification.

    Current targets:
      onetouch  — Seagate OneTouch HDD on Aurora, reached through the
                  chrooted restic SFTP service. This is the off-host copy.
      mp510     — Always-mounted @backup-local btrfs subvolume on the
                  workstation's MP510 NVMe. This is the local copy.

    Every job writes to both targets by default. Family irreplaceable data
    also names both targets explicitly so future target additions do not
    silently change its retention contract.
  */

  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/backup 0755 root root -"
  ];

  # Backup target registry — schema in modules/infra/backup/default.nix.
  nori.backupTargets = {
    onetouch = {
      repository = "sftp:restic@aurora.saola-matrix.ts.net:";
      description = "OneTouch HDD on Aurora; reached over SFTP through the chrooted restic user.";
      tailnetPeer = "aurora.saola-matrix.ts.net";
      extraOptions = [
        "sftp.command='${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/ssh/aurora_known_hosts -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
      ];
    };
    mp510 = {
      repository = "/mnt/backup-local";
      description = "Always-mounted btrfs subvolume on the MP510 NVMe (@backup-local). Drive-based name matching the `onetouch` convention. Replaced the prior `ironwolf` target (data was on the IronWolf @restic-local subvol) in P14 2026-06-11; see modules/machines/workstation/disko-mp510.nix.";
    };
  };

  sops.secrets.restic-ssh-key = {
    owner = "root";
    mode = "0400";
  };

  environment.etc."ssh/aurora_known_hosts".text = ''
    aurora.saola-matrix.ts.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnfMYRv1a3CGvnL0e82w/Z1RK7aOqS3k8JvMYbD8NET
  '';

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

  nori.backups.user-data = {
    include = lib.mapAttrsToList (_: f: f.path) (
      lib.filterAttrs (_: f: f.tier == "user") config.nori.fs
    );
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
    tier = "user";
    timer = "*-*-* 03:00:00";
  };

  /*
    /var/lib/immich/backups is Immich's Pattern B SQL dumps — Immich's
    own scheduled backup writes there (enable in admin web UI: Settings
    → Administration → Backup → Database Dump Settings), restic picks
    it up here as the second half of the consistent point-in-time
    restore plan (per SERVICES.md Pattern B). Not in nori.fs because it's
    NixOS service state, not a structural FS location.

    Aurora's OneTouch receives this tier through restic. The local MP510
    already contains the same irreplaceable paths as Btrfs replicas; writing
    a second restic copy onto that device wastes its backup capacity without
    adding a failure domain.
  */
  nori.backups.media-irreplaceable = {
    include =
      lib.mapAttrsToList (_: f: f.path) (lib.filterAttrs (_: f: f.tier == "irreplaceable") config.nori.fs)
      ++ [ "/var/lib/immich/backups" ];
    tier = "irreplaceable";
    timer = "*-*-* 03:30:00";
    targets = [ "onetouch" ];
  };
}
