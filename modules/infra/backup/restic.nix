{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Shared shell-side iteration helper: emit one
  # "<job> <target> <repoPath>" line per (job, target) pair. The weekly
  # + monthly check scripts read this via a heredoc and loop over
  # them, so the bash side knows nothing about Nix attribute sets.
  activeJobs = lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups;
  pairsShell = lib.concatStringsSep "\n" (
    lib.flatten (
      lib.mapAttrsToList (
        jobName: cfg:
        let
          targets = if cfg.targets == null then lib.attrNames config.nori.backupTargets else cfg.targets;
        in
        map (t: "${jobName} ${t} ${config.nori.backupTargets.${t}.repository}/${jobName}") targets
      ) activeJobs
    )
  );
in
# The cross-cutting infrastructure here — backup targets registry,
# user-data + media-irreplaceable jobs, weekly/monthly check timers —
# is workstation-specific by data ownership: only workstation holds
# the IronWolf media + /srv/share + Immich's dump dir. Other hosts
# that import the services bundle for its route declarations only
# (pi, aurora) get a clean no-op via the hostname gate.
lib.mkIf (config.networking.hostName == "workstation") {
  # Cross-cutting restic infrastructure: the shared password secret,
  # the /var/backup tmpfiles rule that Pattern C2 prepareCommands
  # write into, the backup target declarations, and the weekly +
  # monthly verification timers that iterate over every repo declared
  # via `nori.backups`.
  #
  # Per-job declarations live in the service modules they belong
  # to (`nori.backups.sonarr` in sonarr.nix, etc.) — see
  # modules/infra/backup/default.nix for the abstraction. The non-service-tied
  # jobs (user-data for /home + /srv/share, media-irreplaceable for
  # /mnt/media subvolumes + Immich's Pattern B dump dir) are
  # declared at the bottom of this file because they don't belong
  # to any one service module.
  #
  # Backup targets (the `where`): every job fans out to every target
  # declared below by default. Each (job, target) becomes its own
  # systemd unit `restic-backups-<job>-<target>.service` with
  # independent failure mode + OnFailure → notify@.
  #
  # Current targets:
  #   onetouch  — Seagate OneTouch HDD relocated to aurora on
  #               2026-06-11; reached over SFTP via the chrooted
  #               `restic` user on aurora (machines/aurora/
  #               disko-onetouch.nix + modules/infra/backup/
  #               restic-target.nix). Full failure-domain
  #               independence from workstation now: separate
  #               chassis, PSU, and USB controller.
  #   mp510     — Always-mounted @backup-local btrfs subvolume on the
  #               MP510 NVMe (see disko-mp510.nix). Catches aurora-
  #               unreachable failure mode; doesn't protect against a
  #               workstation drive failure (`mp510` lives in the same
  #               chassis as the source irreplaceable data on the
  #               IronWolf). That's the onetouch target's job (off-
  #               chassis via aurora SFTP).
  #
  # No cloud off-site target — see docs/decisions/0002-aurora-as-
  # family-vault.md. Total-apartment loss is an accepted residual risk;
  # the schema (`nori.backupTargets`) supports remote SFTP if that
  # tolerance ever reverses, but no target is wired today.
  #
  # Roadmap targets:
  #   pi        — Local fast-restore on the appliance once a real
  #               disk replaces the FIT-USB (anti-write storage today).

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
      description = "OneTouch HDD relocated to aurora 2026-06-11; reached over SFTP via the chrooted `restic` user on aurora (see machines/aurora/disko-onetouch.nix + modules/infra/backup/restic-target.nix).";
      extraOptions = [
        "sftp.command='${pkgs.openssh}/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/ssh/aurora_known_hosts -i /run/secrets/restic-ssh-key restic@aurora.saola-matrix.ts.net -s sftp'"
      ];
    };
    mp510 = {
      repository = "/mnt/backup-local";
      description = "Always-mounted btrfs subvolume on the MP510 NVMe (@backup-local). Drive-based name matching the `onetouch` convention. Replaced the prior `ironwolf` target (data was on the IronWolf @restic-local subvol) in P14 2026-06-11; see machines/workstation/disko-mp510.nix.";
    };
  };

  # SSH identity for the chrooted `restic` user on aurora. Private
  # half lives in sops; public half lives in
  # modules/infra/backup/restic-target.nix (authorized_keys).
  # `owner = root` because restic backup units run as root.
  sops.secrets.restic-ssh-key = {
    owner = "root";
    mode = "0400";
  };

  # Pinned aurora host pubkey for SSH host verification. Not a
  # secret — committed in-tree because it lets `BatchMode=yes` ssh
  # invocations verify aurora's identity without a TOFU prompt. If
  # aurora's host key rotates (rare; only on full re-install), grab
  # the new line from `ssh-keyscan -t ed25519
  # aurora.saola-matrix.ts.net` and replace below.
  environment.etc."ssh/aurora_known_hosts".text = ''
    aurora.saola-matrix.ts.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnfMYRv1a3CGvnL0e82w/Z1RK7aOqS3k8JvMYbD8NET
  '';

  # ---------------------------------------------------------------------
  # Backup verification cadence (STORAGE.md § "Backup verification").
  #
  # Two timers in addition to the daily backup runs:
  #   weekly  — `restic check`               (metadata only, fast)
  #   monthly — `restic check --read-data-subset=10%`
  #             (samples 10% of pack data; covers 100% over ~10 months)
  #
  # Both iterate every (job, target) pair derived from `nori.backups`
  # and `nori.backupTargets`. Either step failing for any pair trips
  # OnFailure → notify@ → ntfy.sh urgent alert. A backup that
  # succeeds-but-rots silently is the failure mode this guards against.
  #
  # The wrapper iterates serially (USB HDD; concurrent reads thrash).
  # Failures don't short-circuit — every repo gets attempted so a
  # corrupt repo doesn't hide rot in the others. A pair failure
  # against an offline target (e.g. OneTouch USB unplugged) is also
  # a real signal, not just noise — restic will report
  # "no such file or directory" / "no such device" and the ntfy
  # alert names which target.
  systemd.services.restic-check-weekly = {
    description = "Weekly metadata check of all restic repositories";
    unitConfig.OnFailure = [ "notify@restic-check-weekly.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
    script = ''
      fail=0
      while read job target repo; do
        [ -z "$job" ] && continue
        echo "[$job @ $target] restic check ($repo)"
        if ! ${pkgs.restic}/bin/restic -r "$repo" check; then
          echo "[$job @ $target] FAILED"
          fail=1
        fi
      done <<'EOF'
      ${pairsShell}
      EOF
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
    unitConfig.OnFailure = [ "notify@restic-check-monthly.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
    script = ''
      fail=0
      while read job target repo; do
        [ -z "$job" ] && continue
        echo "[$job @ $target] restic check --read-data-subset=10% ($repo)"
        if ! ${pkgs.restic}/bin/restic -r "$repo" check --read-data-subset=10%; then
          echo "[$job @ $target] FAILED"
          fail=1
        fi
      done <<'EOF'
      ${pairsShell}
      EOF
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

  # Non-service-tied backup repos. Paths derived from nori.fs tier —
  # adding a new subvol in disko-media.nix with `tier = "irreplaceable"`
  # flows through to media-irreplaceable.include automatically; same for
  # `user` → user-data.include.

  nori.backups.user-data = {
    include = lib.mapAttrsToList (_: f: f.path) (
      lib.filterAttrs (_: f: f.tier == "user") config.nori.fs
    );
    tier = "user";
    timer = "*-*-* 03:00:00";
  };

  # /var/lib/immich/backups is Immich's Pattern B SQL dumps — Immich's
  # own scheduled backup writes there (enable in admin web UI: Settings
  # → Administration → Backup → Database Dump Settings), restic picks
  # it up here as the second half of the consistent point-in-time
  # restore plan (per SERVICES.md Pattern B). Not in nori.fs because it's
  # NixOS service state, not a structural FS location.
  #
  # `targets = [ "onetouch" ]` — opted out of the mp510 target because
  # the source data is ~334 GiB of irreplaceable subvolumes on the
  # IronWolf (@photos/@home-videos/@projects/@library/@archive); the
  # mp510 subvol on a different drive in the same chassis could fit
  # it (894 GiB total), but writing the same bytes twice on the same
  # machine doesn't add an independent failure domain. This tier rides
  # the OneTouch (now on aurora over SFTP, separate chassis) alone;
  # cloud off-site explicitly rejected per ADR-0002. Service-tier and
  # user-tier still dual-write — those are small and benefit from the
  # OneTouch-glitch resilience.
  nori.backups.media-irreplaceable = {
    include =
      lib.mapAttrsToList (_: f: f.path) (lib.filterAttrs (_: f: f.tier == "irreplaceable") config.nori.fs)
      ++ [ "/var/lib/immich/backups" ];
    tier = "irreplaceable";
    timer = "*-*-* 03:30:00";
    targets = [ "onetouch" ];
  };
}
