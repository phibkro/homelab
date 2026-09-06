# Enable OneTouch backups after verifying the connection

The prepared destination is the existing OneTouch HDD attached to workstation.
`inventory/backup.nix` keeps `enabled = false` until this procedure passes.
Disabled configuration creates no workstation restic jobs, receiver account,
restore schedules, or OneTouch mount. Pi disabled convergence stops its
role-owned backup schedules and preserves recovery files and credentials.

```text
verify existing drive → safe attachment → verify identity + capacity
 → enable workstation destination → verify SFTP → enable Pi → backup + restore
```

This procedure changes live configuration and requires operator approval.
It does not format a disk or delete existing archives.

## Existing Aurora connection

The operator reports OneTouch remains connected to Aurora. On September 6,
Tailscale reported Aurora offline (last seen August 31, 23:50 UTC), and SSH to
its recorded tailnet address timed out. These observations do not prove that
Aurora is powered off or that its disk is safely removable.

If Aurora becomes reachable, verify its trusted SSH identity, actual OneTouch
mount, repository state, free space and transport credentials before using it
as a temporary backup endpoint. Do not infer repository health from reachability.
Treat it as an external backup endpoint; it need not rejoin the workstation/Pi
deployment inventory. A temporary remote destination requires an explicit,
reviewed transport configuration before sending data.

Before physically moving OneTouch, stop writers and safely unmount it on its
current owner. Do not disconnect a drive whose write activity is unknown.

## Identify and mount the existing filesystem

On workstation, inspect `lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINTS`
and `/dev/disk/by-id/`. Compare the actual device and filesystem against
`inventory/backup.nix`. Its stored OneTouch identity comes from the previous
configuration and has not been verified against an attached drive in this
migration. Correct it from direct evidence if necessary.

The host's `backup-storage.nix` mounts an existing filesystem; it contains no
partitioning or formatting operation. Do not run disko to reconnect this drive.
Record the current workstation generation and Pi revision before activation.

## Verify capacity and recovery credentials

Inspect existing repositories and measure free space, current snapshot coverage,
expected new data, retention growth and maintenance headroom. Preserve old
archives. The media source trees occupied approximately 489 GiB during this
migration; this allocated-size observation is not a compressed backup estimate.

Verify the workstation SSH host public key through a trusted local session.
Compare it with the future Pi host-key pin in inventory. Derive only the public
half of Pi's protected backup credential and compare it with the receiver's
authorized key. Do not display or copy private credentials.

Pi's recorded SSH host key did not match the responding device during the
September 6 preflight. Resolve that through an independently trusted Pi session
before remote administration; do not disable strict checking or accept a scan
as identity proof. Production credential matching remains unverified.

## Enable and verify both senders

Once connection, identity, capacity and credentials pass, change the canonical
backup `enabled` field to true. Build and review workstation first, then activate
it after approval. Confirm the real OneTouch filesystem is mounted at the
declared path and the receiver is restricted to its Pi subtree.

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
