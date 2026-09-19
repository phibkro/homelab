# OneTouch backup evidence — September 19, 2026

The first pass inspected the workstation while stale backup guidance was being
reconciled. Source baseline: `93807ae`; policy enabled by `2810695`.
A later operator-authorized pass ran the workstation service-state restore drill
and weekly repository check. A second authorized pass verified the Pi identity,
sender credential, fresh backup, repository checks, and one configuration
restore. Neither pass deployed a system or changed a source archive. Restore
drills used disposable directories. Times are UTC.

| Layer | Observed evidence | Limit |
|---|---|---|
| Source policy | `inventory/backup.nix` declares `enabled = true`; `tests/eval/backup-enabled.nix` encodes the enabled configuration contract | Source is not deployment evidence; the Nix evaluation test was not rerun during this inspection |
| Physical destination | Host `lsblk` identifies One Touch HDD, serial `00000000NABNR6G2`; host `findmnt /mnt/backup` shows its ext4 partition mounted read/write | Mount and identity do not establish repository or restore health |
| Fresh backups | September 19 journal records saved snapshots and successful jobs for jellyseerr (`8de53346`), vaultwarden (`10c00b4b`), and sonarr (`8c55047a`) | Sampled jobs, not a complete freshness audit |
| Service-state restore | `restore-drill-services.service` exited 0 at 01:41:35; journal reports all 17 repositories restored | File restores and nonempty-file checks; no application startup or database import validation |
| Metadata integrity | `restic-check-weekly.service` exited 0 at 01:44:55; journal records no errors and successful completion | Weekly metadata checks do not read every stored data block |
| Wider restore coverage | `restore-drill-user-data.service` and `restore-drill-all.service` have empty last-exit timestamps in the inspected manager state | No completed user-data/media restore demonstrated by this inspection; a default `Result=success` is not a run |
| Pi | An existing strict hostname pin opened a trusted session to `pi.saola-matrix.ts.net`; the remote hostname, Tailscale address `100.100.71.3`, and `/etc/ssh/ssh_host_ed25519_key.pub` agreed. The installed sender public key and target host pin matched `inventory/backup.nix`; the workstation receiver authorization matched the sender. All eight declared jobs completed fresh snapshots, the freshness check passed, and all eight weekly metadata checks passed. Snapshot `7b076761` restored the Pi-hole repository; the declared local-records file matched its live source byte-for-byte. | The stale address-form `known_hosts` alias was not changed; the verified hostname pin remains authoritative. Only the Pi-hole configuration class was restored and compared. No application/database import, physical reboot, or off-LAN acceptance was performed. |

The deployed service scripts were inspected through `systemctl show ... -p
ExecStart`. The restore script reads `/mnt/backup/$repo`; the weekly script
checks the OneTouch repositories at that mount. This ties the recorded service
outcomes to the inspected destination. The restore drill also computes sample
hashes, but does not compare those hashes against an independent source digest;
the log's sample count is not an application consistency proof.


## Operator-authorized Pi acceptance pass

The second pass used the existing strict hostname pin. It did not replace trust
from `ssh-keyscan`. The trusted session reported:

```text
hostname: pi
Tailscale IPv4: 100.100.71.3
SSH Ed25519 key: AAAAC3NzaC1lZDI1NTE5AAAAILLGrHvVgs+zWudJ5bQv0gwL+ow4wJBXm0p1wNBGBHM2
```

The address-form entry for `100.100.71.3` in the operator's ordinary
`known_hosts` file is stale. It was not used or changed. The hostname-form pin
matched the key read through the trusted session.

The Pi's installed backup key was converted to its public half without reading
the private value into the session. It matched the receiver key declared in
`inventory/backup.nix` and installed at
`/etc/ssh/authorized_keys.d/restic`. The Pi's installed target pin matched the
workstation host public key and the source declaration. The receiver account
remained chrooted to `/mnt/backup/pi`, and a live command attempt was rejected
with `This service allows sftp connections only.`

Before the pass, all eight scheduled backup services and the hourly freshness
check were failed because the newest snapshots exceeded the 36-hour limit. The
operator-authorized run triggered all eight declared jobs:

```text
pihole caddy authelia ntfy beszel victoriametrics victorialogs vector
```

Each service completed successfully. The freshness service then exited zero,
and all eight `check-weekly` metadata services completed successfully. The
Pi-hole run saved snapshot `7b076761`.

The disposable restore helper restored snapshot `7b076761`. The restored
`05-homelab-local-records.conf` matched the live Pi source byte-for-byte. The
new restore directory was removed after comparison. An older restore directory
from September 12 was preserved.

This evidence establishes current transport, fresh snapshots, metadata checks,
and one configuration-file recovery path. It does not establish application
startup, database import, every-file data-block integrity, physical reboot, or
off-LAN behavior.

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
