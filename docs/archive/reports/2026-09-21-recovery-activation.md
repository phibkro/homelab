# Recovery configuration activation — September 21, 2026

This activation applied the accepted recovery configuration to Adelie and the
workstation. It used source revision
`e0596b0f5acc9ee4de3e3e853b9e7d2a7cfab4c2`. Times are UTC unless specified
otherwise.

## Scope

The activation had two goals:

- make Adelie's Stremio backups exclude the reproducible streaming cache;
- make workstation user-data drills restore only three declared samples.

It did not change Pi, move disks, replace production data, or reboot either
host.

## Preflight

The deployment planner selected Adelie before the workstation. It emitted one
NixOS build for each host and no Ansible action.

Both host closures built successfully:

- Adelie: `/nix/store/v2yzikrz9xiprnwglrzj2xcg8gwz9zdl-nixos-system-adelie-26.11.20260910.8ce4ef6`
- workstation: `/nix/store/43gkla5qx5382vi1yak778cyqqiby6jq-nixos-system-workstation-26.11.20260910.8ce4ef6`

Before activation, both hosts reported `running`. OneTouch was mounted read-write
at `/mnt/backup` from `/dev/sdb1` with an Ext4 filesystem.

Adelie's dry activation reported that it would restart `atticd.service` and
`attic-cache-watch.service`. The workstation dry activation reported a
Home Manager restart and an Attic cache watcher restart.

## Adelie activation

`just push adelie` switched Adelie at 03:15:52. The system profile changed from:

`/nix/store/hqh9r8w82hyzl9k6s1ak39nqah3pziyv-nixos-system-adelie-26.11.20260910.8ce4ef6`

To:

`/nix/store/v2yzikrz9xiprnwglrzj2xcg8gwz9zdl-nixos-system-adelie-26.11.20260910.8ce4ef6`

The deployed Stremio backup unit uses this exclusion file:

```text
/var/lib/stremio/stremio-cache
```

After activation:

- Adelie reported `running` with no failed units;
- Stremio, Attic, and the Stremio backup timer were active;
- `curl --fail` accepted Stremio's local `/settings` endpoint;
- the Stremio backup service completed with exit status `0`.

The fresh snapshot was `2a476d7b`, created at 03:17:05. Restic reported a
snapshot size of 8.159 KiB. The prior retained snapshot was 3.319 GiB because it
contained the reproducible cache.

Retention removed one redundant 3.319 GiB daily snapshot. It kept the previous
daily, weekly, and oldest monthly snapshot.

## Workstation activation

`just rebuild` switched the workstation at 03:16:33. The system profile changed
from:

`/nix/store/wxw9043md4rszrrkkgqddn4lza35wgik-nixos-system-workstation-26.11.20260910.8ce4ef6`

To:

`/nix/store/43gkla5qx5382vi1yak778cyqqiby6jq-nixos-system-workstation-26.11.20260910.8ce4ef6`

The deployed user-data drill is now the one-hour bounded unit. The manual
`restore-drill-all` unit now covers service-state repositories only.

After activation:

- the workstation reported `running` with no failed units;
- the user-data drill timer and Attic cache watcher were active;
- OneTouch remained mounted read-write;
- the bounded user-data drill completed with exit status `0`.

The drill restored snapshot `6dcb7308`, created at 02:28:28. It selected one
file from each declared user-data root:

- `/home/nori/.ssh/config`
- `/srv/nori/Documents/abstract_algebra.pdf`
- `/srv/share/projects/homelab/flake.lock`

All three files existed and were readable. The drill reported three files,
235,998 bytes, and a peak memory use of 1.9 GiB.

## Tooling observations

An offline Adelie closure diff was unavailable because Nix rejected unsigned
paths copied from the remote store. The remote dry activation supplied the unit
impact before the switch.

The first SSH verification remained inside the `systemctl` pager and timed out
after the backup had finished. A separate non-paged query confirmed the service
exit status and timestamp. The backup was not run twice.

A direct local Restic read used the workstation repository password against the
Adelie repository. Restic rejected it with `wrong password or no key found`.
That read changed no repository data. The accepted snapshot evidence comes from
Adelie's deployed service and journal.

## Evidence boundary

This activation establishes the deployed cache exclusion and bounded drill
behavior. It also proves one fresh Stremio backup and one bounded user-data
restore after activation.

It does not establish:

- a restore of the new cache-excluded Stremio snapshot;
- complete user-data or media recovery;
- every-file data-block integrity;
- physical host or disk replacement;
- reboot persistence;
- Pi deployment or off-LAN acceptance.
