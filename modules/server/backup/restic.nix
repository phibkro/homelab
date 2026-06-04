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
        map (t: "${jobName} ${t} ${config.nori.backupTargets.${t}.repoBase}/${jobName}") targets
      ) activeJobs
    )
  );
in
{
  # Cross-cutting restic infrastructure: the shared password secret,
  # the /var/backup tmpfiles rule that Pattern C2 prepareCommands
  # write into, the backup target declarations, and the weekly +
  # monthly verification timers that iterate over every repo declared
  # via `nori.backups`.
  #
  # Per-job declarations live in the service modules they belong
  # to (`nori.backups.sonarr` in sonarr.nix, etc.) — see
  # modules/effects/backup.nix for the abstraction. The non-service-tied
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
  #   onetouch  — USB OneTouch ext4 mount at /mnt/backup (formatted via
  #               machines/workstation/disko-onetouch.nix). Different
  #               physical drive from IronWolf data + SN750 root,
  #               same chassis + PSU + USB hub. Failure-domain
  #               independence is partial: drives apart, but USB-side
  #               glitches affect this one specifically (2026-06-04
  #               wedged-controller incident).
  #   ironwolf  — Always-mounted @restic-local btrfs subvolume on the
  #               IronWolf media drive (see disko-media.nix). Catches
  #               OneTouch-offline failure mode; doesn't protect
  #               against a full IronWolf drive failure (the source
  #               irreplaceable data lives there too).
  #
  # Roadmap targets:
  #   hetzner   — Off-site Hetzner Storage Box via SFTP (true
  #               geographic resilience for irreplaceable tier).
  #   pi        — Local fast-restore on the appliance once a real
  #               disk replaces the FIT-USB (anti-write storage today).

  sops.secrets.restic-password = {
    owner = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/backup 0755 root root -"
  ];

  # ---------------------------------------------------------------------
  # Backup target registry. See modules/effects/backup.nix for the
  # schema; each nori.backups.<job> fans out to every target listed
  # here by default, producing one restic-backups-<job>-<target>
  # systemd unit per pair.
  nori.backupTargets = {
    onetouch = {
      repoBase = "/mnt/backup";
      description = "USB OneTouch external HDD — autofs lazy-mount; can survive workstation reboot.";
    };
    ironwolf = {
      repoBase = "/mnt/backup-local";
      description = "Always-mounted btrfs subvolume on the IronWolf media drive (@restic-local).";
    };
  };

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

  # ---------------------------------------------------------------------
  # Non-service-tied backup repos. Service-specific repos live in the
  # respective service modules (modules/server/<name>.nix).
  #
  # Paths derived from nori.fs tier — host's disko config is the single
  # source of truth (see modules/effects/fs.nix). Adding a new media
  # subvolume in disko-media.nix with `tier = "irreplaceable"` flows
  # through to media-irreplaceable.include automatically; same for `user`
  # → user-data.include.

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
  # `targets = [ "onetouch" ]` — opted out of the ironwolf target because
  # the source data IS the irreplaceable subvolumes on the IronWolf
  # itself (@photos/@home-videos/@projects/@library/@archive). Backing
  # those up to a sibling subvolume on the same drive would (a) come
  # close to doubling drive usage (3.0T used of 3.7T already as of
  # 2026-06-04 — wouldn't fit) and (b) provide zero protection against
  # the failure mode same-drive-backup can't catch (full IronWolf
  # drive failure). Until Hetzner off-site lands, this tier rides
  # the OneTouch alone. Service-tier and user-tier still dual-write —
  # those are small and benefit from the OneTouch-glitch resilience.
  nori.backups.media-irreplaceable = {
    include =
      lib.mapAttrsToList (_: f: f.path) (lib.filterAttrs (_: f: f.tier == "irreplaceable") config.nori.fs)
      ++ [ "/var/lib/immich/backups" ];
    tier = "irreplaceable";
    timer = "*-*-* 03:30:00";
    targets = [ "onetouch" ];
  };
}
