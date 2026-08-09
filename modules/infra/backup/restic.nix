{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Same lock-retrying restic the backup units run — `check` takes the
  # EXCLUSIVE lock that the 2026-08-09 incident collided with, so it has
  # to queue behind a running backup for exactly the same reason.
  resticCli = import ./restic-cli.nix pkgs;

  /*
    Shared (job, target) iteration for the weekly + monthly check
    scripts: emit one `check_repo` call per pair, carrying the
    target's TRANSPORT config alongside the repo path — the `-o`
    flags from `extraOptions` and the `environmentFile`, if any.

    Load-bearing: the generated backup units inherit `extraOptions` +
    `environmentFile` from the target (modules/infra/backup/default.nix
    § services.restic.backups), so a check that omits them speaks a
    different transport than the backup that wrote the repo. For the
    `onetouch` SFTP target that meant bare `ssh restic@aurora` with no
    identity file and no pinned known_hosts → "Permission denied
    (publickey)" every Sunday, while the backups themselves stayed
    green. See docs/reports/20260718-115850-restic-check-weekly-failure.md.
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

    extraOptions are interpolated RAW, not escapeShellArg'd: the
    `sftp.command='ssh …'` value carries shell-quotes meant to be STRIPPED
    by the parser — systemd's ExecStart strips them for the backup units,
    so a bash check script must too. Escaping preserved them literally, so
    restic tried to fork/exec the whole `ssh -o … -s sftp` string as one
    binary ("no such file or directory"). One inline restic call per pair
    (rather than a `"$@"`-forwarding function) keeps the quoting identical
    to the backups. Verified against the real aurora handshake 2026-07-18
    — the seam a disposable clone couldn't reach.
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
            ${envPrefix}${lib.getExe resticCli} ${extraOpts} -r ${lib.escapeShellArg repo} unlock >/dev/null 2>&1 || true
            ${lib.getExe resticCli} ${extraOpts} -r ${lib.escapeShellArg repo} check ${flags}
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
    jobs (user-data for /home + /srv/share, media-irreplaceable for
    /mnt/media subvolumes + Immich's Pattern B dump dir) are
    declared at the bottom of this file because they don't belong
    to any one service module.

    Backup targets (the `where`): every job fans out to every target
    declared below by default. Each (job, target) becomes its own
    systemd unit `restic-backups-<job>-<target>.service` with
    independent failure mode + OnFailure → notify@.

    Current targets:
      onetouch  — Seagate OneTouch HDD relocated to aurora on
                  2026-06-11; reached over SFTP via the chrooted
                  `restic` user on aurora (machines/aurora/
                  disko-onetouch.nix + modules/infra/backup/
                  the restic-target workload). Full failure-domain
                  independence from workstation now: separate
                  chassis, PSU, and USB controller.
      mp510     — Always-mounted @backup-local btrfs subvolume on the
                  MP510 NVMe (see disko-mp510.nix). Catches aurora-
                  unreachable failure mode; doesn't protect against a
                  workstation drive failure (`mp510` lives in the same
                  chassis as the source irreplaceable data on the
                  IronWolf). That's the onetouch target's job (off-
                  chassis via aurora SFTP).

    No cloud off-site target — see docs/decisions/0002-aurora-as-
    family-vault.md. Total-apartment loss is an accepted residual risk;
    the schema (`nori.backupTargets`) supports remote SFTP if that
    tolerance ever reverses, but no target is wired today.

    Roadmap targets:
      pi        — Local fast-restore on the appliance once a real
                  disk replaces the FIT-USB (anti-write storage today).
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
      description = "OneTouch HDD relocated to aurora 2026-06-11; reached over SFTP via the chrooted `restic` user on aurora (see modules/machines/aurora/disko-onetouch.nix + the restic-target workload).";
      extraOptions = [
        "sftp.command='${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/ssh/aurora_known_hosts -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
      ];
    };
    mp510 = {
      repository = "/mnt/backup-local";
      description = "Always-mounted btrfs subvolume on the MP510 NVMe (@backup-local). Drive-based name matching the `onetouch` convention. Replaced the prior `ironwolf` target (data was on the IronWolf @restic-local subvol) in P14 2026-06-11; see modules/machines/workstation/disko-mp510.nix.";
    };
  };

  /*
    SSH identity for the chrooted `restic` user on aurora. Private
    half lives in sops; public half lives in
    modules/infra/backup/restic-target/runtime.nix (authorized_keys).
    `owner = root` because restic backup units run as root.
  */
  sops.secrets.restic-ssh-key = {
    owner = "root";
    mode = "0400";
  };

  /*
    Pinned aurora host pubkey for SSH host verification. Not a
    secret — committed in-tree because it lets `BatchMode=yes` ssh
    invocations verify aurora's identity without a TOFU prompt. If
    aurora's host key rotates (rare; only on full re-install), grab
    the new line from `ssh-keyscan -t ed25519
    aurora.saola-matrix.ts.net` and replace below.
  */
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

    `targets = [ "onetouch" ]` — opted out of the mp510 target because
    the source data is ~334 GiB of irreplaceable subvolumes on the
    IronWolf (@photos/@home-videos/@projects/@library/@archive); the
    mp510 subvol on a different drive in the same chassis could fit
    it (894 GiB total), but writing the same bytes twice on the same
    machine doesn't add an independent failure domain. This tier rides
    the OneTouch (now on aurora over SFTP, separate chassis) alone;
    cloud off-site explicitly rejected per ADR-0002. Service-tier and
    user-tier still dual-write — those are small and benefit from the
    OneTouch-glitch resilience.
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
