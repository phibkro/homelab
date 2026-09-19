# OneTouch backup evidence — September 19, 2026

Read-only inspection from workstation while reconciling stale disabled-backup
documentation. Source baseline: `93807ae`; policy enabled by `2810695`.
No backup, restore, deployment, credential access, or disk mutation was triggered
by this inspection. Times below are UTC.

| Layer | Observed evidence | Limit |
|---|---|---|
| Source policy | `inventory/backup.nix` declares `enabled = true`; `tests/eval/backup-enabled.nix` encodes the enabled configuration contract | Source is not deployment evidence; the Nix evaluation test was not rerun during this inspection |
| Physical destination | Host `lsblk` identifies One Touch HDD, serial `00000000NABNR6G2`; host `findmnt /mnt/backup` shows its ext4 partition mounted read/write | Mount and identity do not establish repository or restore health |
| Fresh backups | September 19 journal records saved snapshots and successful jobs for jellyseerr (`8de53346`), vaultwarden (`10c00b4b`), and sonarr (`8c55047a`) | Sampled jobs, not a complete freshness audit |
| Service-state restore | `restore-drill-services.service` exited 0 at 01:41:35; journal reports all 17 repositories restored | File restores and nonempty-file checks; no application startup or database import validation |
| Metadata integrity | `restic-check-weekly.service` exited 0 at 01:44:55; journal records no errors and successful completion | Weekly metadata checks do not read every stored data block |
| Wider restore coverage | `restore-drill-user-data.service` and `restore-drill-all.service` have empty last-exit timestamps in the inspected manager state | No completed user-data/media restore demonstrated by this inspection; a default `Result=success` is not a run |
| Pi | No remote session or Pi repository inspection performed | No claim about Pi backup freshness, restored state, or production transport isolation |

The deployed service scripts were inspected through `systemctl show ... -p
ExecStart`. The restore script reads `/mnt/backup/$repo`; the weekly script
checks the OneTouch repositories at that mount. This ties the recorded service
outcomes to the inspected destination. The restore drill also computes sample
hashes, but does not compare those hashes against an independent source digest;
the log's sample count is not an application consistency proof.

## Reproduce the read-only inspection

```bash
lsblk -o NAME,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
findmnt /mnt/backup
systemctl show restic-check-weekly.service restore-drill-services.service \
  restore-drill-user-data.service restore-drill-all.service \
  -p Id -p Result -p ExecMainExitTimestamp -p ExecMainStatus
journalctl --utc --no-pager --since '2026-09-19' \
  -u restore-drill-services -u restic-check-weekly
journalctl --utc --no-pager --since '2026-09-18' -u 'restic-backups-*'
```

Host inspection matters: the agent's filesystem sandbox exposed the backup
mount read-only and blocked the system bus. The host checks above established
the actual mount options and service outcomes; sandbox observations were not
treated as host failures.

For a new connection, transport change, or application recovery test, use the
[OneTouch runbook](../../runbooks/onetouch-backup-cutover.md). Preserve existing
archives and collect fresh evidence for the data being recovered.
