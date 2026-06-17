{
  config,
  lib,
  pkgs,
  ...
}:

let
  /**
    Drill repo tiers — split so failures are isolated and cadence
    matches cost. The split surfaced 2026-06-07 after one user-data
    red mask 17 GREEN service drills in the alert payload.

    Workstation-only by data ownership — same gate as the sibling
    backup/restic.nix. Other hosts importing the bundle (pi, aurora)
    don't have the source data being restored here OR the
    restic-password sops secret this script consumes.

    - `serviceRepos`  — the 17 service-state repos. Cheap (~few min
                        total). Monthly drill cadence.
    - `userDataRepos` — user-data tier (irreplaceable personal state).
                        Heavy (~99 GiB, 30+ min). Quarterly cadence.
    - `mediaRepos`    — media-irreplaceable (hundreds of GB). NEVER
                        in automated drill — manual only via
                        `restore-drill-all.service`. Weekly
                        `restic check` + monthly read-data-subset
                        already verify pack integrity.

    Repos with `paths` set (skip explicit-opt-out entries).
  */
  activeRepos = lib.attrNames (lib.filterAttrs (_: cfg: cfg.include != null) config.nori.backups);
  userDataRepos = lib.filter (n: n == "user-data") activeRepos;
  serviceRepos = lib.filter (n: n != "user-data" && n != "media-irreplaceable") activeRepos;
in
lib.mkIf (config.networking.hostName == "workstation") (
  let

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
          if ! ${pkgs.restic}/bin/restic -r "/mnt/backup/$repo" restore latest \
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
  in
  {
    /**
      Restore drills — verify backups are not just *recorded* (which
      `restic check` confirms) but actually *restorable*. Three units
      by tier; cadence matches blast-radius and runtime cost:

        restore-drill-services   — 17 service repos. Monthly. ~5 min.
                                   Cheap signal, runs often.
        restore-drill-user-data  — user-data tier. Quarterly. ~30 min.
                                   Irreplaceable personal state.
        restore-drill-all        — everything incl. media. Manual only.
                                   Multi-hour. Deep audits.

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
      description = "Monthly restore drill — service-state tier";
      after = [ "mnt-backup.mount" ];
      requires = [ "mnt-backup.mount" ];
      unitConfig.OnFailure = [ "notify@restore-drill-services.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # Service-state restores are quick (largest is jellyfin at ~1 GiB).
        # Allow generous headroom for restic warm-cache + sample sha256.
        TimeoutStartSec = "1h";
      };
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
      };
    };

    systemd.services.restore-drill-user-data = {
      description = "Quarterly restore drill — user-data tier (heavy)";
      after = [ "mnt-backup.mount" ];
      requires = [ "mnt-backup.mount" ];
      unitConfig.OnFailure = [ "notify@restore-drill-user-data.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # user-data is ~99 GiB; allow 4h for the restore + sample verify.
        TimeoutStartSec = "4h";
      };
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = drillScript userDataRepos;
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
      };
    };

    /**
      Manual deep-audit — restores everything including
      media-irreplaceable. Multi-hour disk I/O. Trigger with
      `sudo systemctl start restore-drill-all.service`. No timer.
    */
    systemd.services.restore-drill-all = {
      description = "Restore drill — full pass including media-irreplaceable";
      after = [ "mnt-backup.mount" ];
      requires = [ "mnt-backup.mount" ];
      unitConfig.OnFailure = [ "notify@restore-drill-all.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        TimeoutStartSec = "12h";
      };
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
      script = drillScript activeRepos;
    };
  }
)
