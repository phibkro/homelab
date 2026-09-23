{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  /**
    Drill repo tiers — split so failures are isolated and cadence
    matches cost. The split surfaced 2026-06-07 after one user-data
    red mask the successful service drills in the alert payload.

    Reusable restore drills for hosts that explicitly select a backup policy.
    It schedules nothing while the inventory backup policy is disabled.

    - `serviceRepos`  — active service-state repos. Cheap (~few min
                        total). Monthly drill cadence.
    - `userDataRepos` — user-data tier (irreplaceable personal state).
                        Quarterly bounded file restore. Full snapshots are too
                        large for the workstation root filesystem.
    - `media-irreplaceable` is never restored automatically. Weekly
      `restic check` and monthly read-data-subset verify pack integrity.
      Manual recovery selects an explicit destination with enough capacity.

    Repos with `paths` set (skip explicit-opt-out entries).
  */
  activeRepos = lib.attrNames (lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups);
  userDataRepos = lib.filter (n: n == "user-data") activeRepos;
  serviceRepos = lib.filter (n: n != "user-data" && n != "media-irreplaceable") activeRepos;
  serviceRepoCount = lib.length serviceRepos;
  userDataRepo = lib.findFirst (n: n == "user-data") null activeRepos;
  userDataSamples =
    if userDataRepo == null then [ ] else config.nori.backups.${userDataRepo}.restoreSamples;

  # Restore from the same declared target as the backup writer.
  drillRepositoryRoot = config.nori.inventory.backup.mountPoint;
  drillMountUnit = "${utils.escapeSystemdPath drillRepositoryRoot}.mount";

  # Restore verification is maintenance work: contain its memory and yield
  # CPU/disk to the desktop, SSH, and production services.
  drillServiceConfig = timeout: {
    Type = "oneshot";
    User = "root";
    Nice = 15;
    CPUSchedulingPolicy = "batch";
    IOSchedulingClass = "idle";
    CPUWeight = 10;
    IOWeight = 10;
    MemoryHigh = "4G";
    MemoryMax = "8G";
    OOMPolicy = "stop";
    TimeoutStartSec = timeout;
  };

  drillScript = repos: ''
    # NixOS's systemd.services.*.script prepends `set -e` to the body. # multi-line: ok
    # Combined with `pipefail` below it interrupts the loop on the first
    # transient pipeline failure (e.g. a flaky sha256sum sample on a
    # jellyfin metadata file vanishing mid-walk), defeating the script's
    # OWN failure model (accumulate `fail=1 + continue`, summary at end).
    # Disable errexit explicitly — keep pipefail so `if !` still catches
    # restic's real exit.
    set +e
    set -uo pipefail
    timestamp=$(date +%Y%m%d-%H%M%S)
    logdir=/var/log/restore-drill
    restoredir=/var/restore-test
    mkdir -p "$logdir" "$restoredir"
    log="$logdir/$timestamp.txt"

    fail=0
    {
      echo "=== Restore drill at $timestamp ==="
      echo "Repos: ${lib.concatStringsSep ", " repos}"
      echo

      for repo in ${lib.concatStringsSep " " repos}; do
        target="$restoredir/$repo-$timestamp"
        mkdir -p "$target"
        echo "──── [$repo] ────"
        echo "  restoring latest snapshot to $target"
        if ! ${pkgs.restic}/bin/restic -r "${drillRepositoryRoot}/$repo" restore latest \
            --target "$target" >/dev/null 2>&1; then
          echo "  ✗ RESTORE FAILED"
          fail=1
          continue
        fi

        file_count=$(find "$target" -type f 2>/dev/null | wc -l)
        total_bytes=$(${pkgs.coreutils}/bin/du -sb "$target" 2>/dev/null | cut -f1)
        # Sample sha256 of 20 random files — confirms the restored
        # bytes are readable and consistent with what restic stored.
        sample=$(find "$target" -type f 2>/dev/null \
          | ${pkgs.coreutils}/bin/shuf -n 20 \
          | xargs -I{} ${pkgs.coreutils}/bin/sha256sum {} 2>/dev/null | wc -l)

        if [ "$file_count" -eq 0 ]; then
          echo "  ✗ EMPTY: 0 files restored — symlink-only snapshot? (DynamicUser path bug?)"
          fail=1
          continue
        fi
        echo "  ✓ files=$file_count bytes=$total_bytes sha256_sampled=$sample"
      done

      echo
      echo "=== Cleanup ==="
      find "$restoredir" -mindepth 1 -maxdepth 1 -type d -mtime +30 -print -exec rm -rf {} +
      find "$logdir" -name '*.txt' -mtime +180 -print -delete

      if [ "$fail" -eq 0 ]; then
        echo "=== PASS — all $(echo ${lib.concatStringsSep " " repos} | wc -w) repos restored cleanly ==="
      else
        echo "=== FAIL — at least one repo did not restore cleanly ==="
      fi
    } 2>&1 | ${pkgs.coreutils}/bin/tee -a "$log"

    exit $fail
  '';

  sampledDrillScript =
    repo: samples:
    let
      includeArgs = lib.concatMapStringsSep " " (
        sample: "--include=${lib.escapeShellArg sample}"
      ) samples;
      sampleWords = lib.concatMapStringsSep " " lib.escapeShellArg samples;
    in
    ''
      set -euo pipefail
      timestamp=$(date +%Y%m%d-%H%M%S)
      logdir=/var/log/restore-drill
      target=/var/restore-test/${repo}-$timestamp
      log="$logdir/$timestamp.txt"
      mkdir -p "$logdir" "$target"

      {
        echo "=== Bounded restore drill at $timestamp ==="
        echo "Repo: ${repo}"
        echo "Restoring ${toString (lib.length samples)} declared samples"

        ${pkgs.restic}/bin/restic -r "${drillRepositoryRoot}/${repo}" restore latest \
          --target "$target" ${includeArgs}

        for sample in ${sampleWords}; do
          restored="$target$sample"
          if [ ! -f "$restored" ]; then
            echo "✗ MISSING: $sample"
            exit 1
          fi
          ${pkgs.coreutils}/bin/sha256sum "$restored" >/dev/null
          echo "✓ $sample"
        done

        file_count=$(${pkgs.findutils}/bin/find "$target" -type f | ${pkgs.coreutils}/bin/wc -l)
        total_bytes=$(${pkgs.coreutils}/bin/du -sb "$target" | ${pkgs.coreutils}/bin/cut -f1)
        echo "=== PASS — files=$file_count bytes=$total_bytes samples=${toString (lib.length samples)} ==="

        ${pkgs.findutils}/bin/find /var/restore-test -mindepth 1 -maxdepth 1 \
          -type d -mtime +30 -print -exec ${pkgs.coreutils}/bin/rm -rf {} +
        ${pkgs.findutils}/bin/find "$logdir" -name '*.txt' -mtime +180 -print -delete
      } 2>&1 | ${pkgs.coreutils}/bin/tee -a "$log"
    '';
in
{
  config = lib.mkIf config.nori.inventory.backup.enabled {
    assertions = [
      {
        assertion = userDataRepos == [ ] || userDataSamples != [ ];
        message = "The user-data backup requires restoreSamples for its bounded quarterly drill.";
      }
    ];
    /**
      Restore drills — verify backups are not just *recorded* (which
      `restic check` confirms) but actually *restorable*. Three units
      by tier; cadence matches blast-radius and runtime cost:

        restore-drill-services   — full restore of active service repositories.
                                   Monthly; cheap and broad.
        restore-drill-user-data  — bounded user-data sample restore. Quarterly.
                                   Exercises every declared user-data root.
        restore-drill-all        — full service-state pass. Manual only.

      Output:
        /var/log/restore-drill/<timestamp>.txt   one log per run
        /var/restore-test/<repo>-<timestamp>/    restored data, kept 30d

      ntfy alert on failure via OnFailure → notify@ template per unit.
    */

    systemd.tmpfiles.rules = [
      "d /var/restore-test 0700 root root -"
      "d /var/log/restore-drill 0750 root root -"
    ];

    systemd.services.restore-drill-services = {
      description = "Monthly restore drill — ${toString serviceRepoCount} service-state repositories";
      after = [ drillMountUnit ];
      requires = [ drillMountUnit ];
      unitConfig.OnFailure = [ "notify@restore-drill-services.service" ];
      # Service-state restores are quick (largest is jellyfin at ~1 GiB).
      # Allow generous headroom for restic warm-cache + sample sha256.
      serviceConfig = drillServiceConfig "1h";
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = drillScript serviceRepos;
    };

    systemd.timers.restore-drill-services = {
      description = "Monthly service-tier restore drill timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # First Sunday of the month at 04:00. Services are cheap to drill
        # so monthly cadence gives faster signal on backup-side regression.
        OnCalendar = "Sun *-*-01..07 04:00:00";
        Persistent = true;
        # Avoid a thundering start at calendar/boot/deployment boundaries.
        # FixedRandomDelay keeps the chosen offset stable across restarts.
        RandomizedDelaySec = "6h";
        FixedRandomDelay = true;
        AccuracySec = "15min";
      };
    };

    systemd.services.restore-drill-user-data = {
      description = "Quarterly bounded restore drill — user-data tier";
      after = [ drillMountUnit ];
      requires = [ drillMountUnit ];
      unitConfig.OnFailure = [ "notify@restore-drill-user-data.service" ];
      serviceConfig = drillServiceConfig "1h";
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = sampledDrillScript userDataRepo userDataSamples;
    };

    systemd.timers.restore-drill-user-data = {
      description = "Quarterly user-data restore drill timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        /*
          First Sunday of each quarter (Jan/Apr/Jul/Oct) at 05:00.
          Offset 1h from the services drill to keep the disk I/O windows
          separate. Every month has a Sunday in days 1..7.
        */
        OnCalendar = "Sun *-01,04,07,10-01..07 05:00:00";
        Persistent = true;
        RandomizedDelaySec = "6h";
        FixedRandomDelay = true;
        AccuracySec = "15min";
      };
    };

    /**
      Manual full service-state audit. Large user-data and media repositories
      require an explicit restore destination with enough capacity and are not
      included in this root-filesystem unit.
    */
    systemd.services.restore-drill-all = {
      description = "Restore drill — full service-state pass";
      after = [ drillMountUnit ];
      requires = [ drillMountUnit ];
      unitConfig.OnFailure = [ "notify@restore-drill-all.service" ];
      serviceConfig = drillServiceConfig "4h";
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = drillScript serviceRepos;
    };
  };
}
