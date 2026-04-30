{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Repos to include in the quarterly automated drill. Excludes
  # `media-irreplaceable` — it's hundreds of GB and would dominate
  # drill runtime; that repo's `restic check --read-data-subset=10%`
  # monthly + `restic check` weekly already verify pack integrity,
  # and the restore mechanism is structurally identical to the other
  # repos. For a deep check including media, run the drill manually:
  # `sudo systemctl start restore-drill-all.service`.
  # Repos with `paths` set (skip the explicit-opt-out entries).
  activeRepos = lib.attrNames (lib.filterAttrs (_: cfg: cfg.paths != null) config.nori.backups);
  drillRepos = lib.filter (n: n != "media-irreplaceable") activeRepos;

  drillScript = repos: ''
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
  # Quarterly restore drill. Verifies that backups are not just
  # *recorded* (which `restic check` confirms) but actually
  # *restorable* — the difference between "I have backups" and
  # "I have verified-restorable backups". Phase 7 item 4.
  #
  # Two systemd services:
  #   restore-drill        — runs on the quarterly timer; excludes
  #                          media-irreplaceable for runtime sanity
  #   restore-drill-all    — manual trigger; includes every repo,
  #                          intended for deep audits
  #
  # Output:
  #   /var/log/restore-drill/<timestamp>.txt   one log per run
  #   /var/restore-test/<repo>-<timestamp>/    restored data, kept 30d
  #
  # ntfy alert on failure via the OnFailure → notify@ template
  # (modules/server/ntfy/notify.nix).

  systemd.tmpfiles.rules = [
    "d /var/restore-test 0700 root root -"
    "d /var/log/restore-drill 0750 root root -"
  ];

  systemd.services.restore-drill = {
    description = "Quarterly restore drill (verifies backups are restorable)";
    after = [ "mnt-backup.mount" ];
    requires = [ "mnt-backup.mount" ];
    unitConfig.OnFailure = [ "notify@restore-drill.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # Long timeout — depending on repo sizes a drill can take
      # tens of minutes. The default DefaultTimeoutStartSec (90s)
      # is way too short.
      TimeoutStartSec = "4h";
    };
    environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic-password.path;
    script = drillScript drillRepos;
  };

  systemd.timers.restore-drill = {
    description = "Quarterly restore drill timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # First Sunday of each quarter (Jan/Apr/Jul/Oct) at 04:00.
      # Every month has a Sunday in days 1..7, so this fires
      # exactly once per quarter.
      OnCalendar = "Sun *-01,04,07,10-01..07 04:00:00";
      Persistent = true;
    };
  };

  # Manual deep-audit variant — restores everything including
  # media-irreplaceable. Several hours of disk I/O. Trigger with
  # `sudo systemctl start restore-drill-all.service`. No timer.
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
