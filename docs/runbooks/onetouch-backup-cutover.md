# Verify or reconnect OneTouch backups

Use this procedure when reconnecting the existing OneTouch HDD, changing its
transport, or verifying recovery. [`inventory/backup.nix`](../../inventory/backup.nix)
owns the current enable switch; this runbook is not a declaration that backups
are disabled. The [September 19 inspection](../archive/reports/2026-09-19-backup-evidence.md)
records the enabled policy and observed workstation backup/restore evidence.

```text
verify existing drive → safe attachment → verify identity + capacity
 → enable workstation destination → verify SFTP → enable Pi → backup + restore
```

This procedure changes live configuration and requires operator approval.
It does not format a disk or delete existing archives.

## Historical Aurora connection

During the September 6 preflight, the operator reported OneTouch on Aurora.
Tailscale reported Aurora offline (last seen August 31, 23:50 UTC), and SSH to
its recorded tailnet address timed out. These observations do not prove that
Aurora is powered off or that its disk is safely removable.

If Aurora becomes reachable, verify its trusted SSH identity, actual OneTouch
mount, repository state, free space and transport credentials before using it
as a temporary backup endpoint. Do not infer repository health from reachability.
Treat it as an external backup endpoint; it need not rejoin the workstation/Pi
deployment inventory. A temporary remote destination requires an explicit,
reviewed transport configuration before sending data.

The September 19 inspection found OneTouch mounted on workstation. Before any
future physical move, stop writers and safely unmount it on its
current owner. Do not disconnect a drive whose write activity is unknown.

## Identify and mount the existing filesystem

On workstation, inspect `lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINTS`
and `/dev/disk/by-id/`. Compare the actual device and filesystem against
`inventory/disks.nix`. Correct the registry from direct evidence if necessary.

The host's `backup-storage.nix` mounts an existing filesystem; it contains no
partitioning or formatting operation. Do not run disko to reconnect this drive.
Record the current workstation generation and Pi revision before activation.

## Verify capacity and recovery credentials

Inspect existing repositories and measure free space, current snapshot coverage,
expected new data, retention growth and maintenance headroom. Preserve old
archives. The media source trees occupied approximately 489 GiB during this
migration; this allocated-size observation is not a compressed backup estimate.

Verify the workstation SSH host public key through a trusted local session.
Compare it with the Pi host-key pin in inventory. Derive only the public
half of Pi's protected backup credential and compare it with the receiver's
authorized key. Do not display or copy private credentials.

Pi's recorded SSH host key did not match the responding device during the
September 6 preflight. Resolve that through an independently trusted Pi session
before remote administration; do not disable strict checking or accept a scan
as identity proof. That preflight did not verify production credential matching;
recheck it when changing or recovering the transport.

## Enable and verify both senders

If the canonical backup policy is disabled, enable it only after connection,
identity, capacity and credentials pass. For configuration changes, build and
review workstation first, then activate it after approval. Confirm the real
OneTouch filesystem is mounted at the declared path and the receiver is
restricted to its Pi subtree.

From Pi, use the pinned transport to verify a disposable write/read within that
subtree. Confirm sibling workstation repositories and shell execution are
inaccessible. Remove only the test file you created.

Generate inventory, run `just pi::plan`, review it, then deploy Pi after approval.
For both hosts, trigger fresh jobs from the evaluated manifest, record snapshot
IDs, run integrity checks and restore into disposable directories. Compare
restored content with the backed-up source. Validate database dumps separately;
a successful file restore alone does not prove application recovery.

Existing MP510 archives remain preserved until a separately approved relocation
or retention decision. Policy changes in `.sops.yaml` do not re-encrypt old
ciphertext or revoke historical recipients; rekeying is separate work.
