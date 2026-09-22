---
summary: Current destructive workstation installation procedure, disk-identity gates, and recovery handoff.
---

# Workstation bare-metal install

Use this procedure for a new workstation install or a replacement root disk.
For recovery after a root-disk failure, also follow the
[root-drive runbook](../runbooks/drive-failure-root.md).

This procedure destroys the selected disk. It requires explicit operator
approval after the disk identity and source revision are reviewed.

## Preconditions

Before booting the installer:

1. Choose the exact repository revision and keep its existing `flake.lock`.
2. Review `infra/workstation/disko.nix` and its `/dev/disk/by-id/` target.
3. Record the model and serial for every attached disk.
4. Verify recent OneTouch snapshots and the restore evidence needed for this
   install.
5. Preserve the MP510, IronWolf Pro, OneTouch, and every other non-target disk.
6. Keep a trusted path for restoring or replacing the workstation SSH host key.

Do not assume that a device such as `/dev/nvme0n1` identifies the same physical
disk after a reboot. The current disk declaration uses a stable by-id path.
A replacement disk has a different path. Update and review the declaration
before running Disko.

## Install

### 1. Boot the installer

Boot a current NixOS minimal installer in UEFI mode. Enable the network, then
enter a root shell.

```bash
sudo -i
ping -c 2 cache.nixos.org
```

### 2. Obtain the intended source

Place the intended homelab checkout at `/tmp/homelab`. A remote clone is valid
only when the required revision was published. Otherwise, copy the reviewed
checkout through a trusted local or SSH path.

```bash
cd /tmp/homelab
git rev-parse HEAD
```

Compare the result with the approved revision. Do not update `flake.lock` during
recovery or installation unless that separate source change was approved.

### 3. Verify disk identity

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
ls -l /dev/disk/by-id/
```

Match the approved target by model, serial, and by-id path. Confirm that
`infra/workstation/disko.nix` selects only that disk. Stop if any identity is
missing or different.

Disconnect removable non-target disks when practical. Disko scope and disk
identity remain the required safeguards for internal disks.

### 4. Apply the reviewed layout

```bash
disko_rev="$(
  nix eval --impure --raw --expr \
    '(builtins.fromJSON (builtins.readFile /tmp/homelab/flake.lock)).nodes.disko.locked.rev'
)"
nix --extra-experimental-features 'nix-command flakes' \
  run "github:nix-community/disko/${disko_rev}" -- \
  --mode disko /tmp/homelab/infra/workstation/disko.nix
```

This command is destructive. It creates the current Btrfs and EFI layout from
the reviewed source. Do not re-run Disko against IronWolf, MP510, OneTouch, or a
disk that may still contain recoverable data.

Inspect the result before installation:

```bash
findmnt -R /mnt
```

### 5. Recreate disk swap and refresh resume identity

The root filesystem stores `/swapfile` outside Disko. Formatting the root
filesystem changes its UUID and invalidates the recorded hibernation offset.
Create the file on the mounted target:

```bash
btrfs filesystem mkswapfile --size 32g /mnt/swapfile
findmnt -no UUID /mnt
btrfs inspect-internal map-swapfile -r /mnt/swapfile
```

Update `boot.resumeDevice` and the `resume_offset` kernel parameter in
`infra/workstation/hardware.nix` with these observed values. Review and commit
that source change before installation. Do not reuse values from the old
filesystem.

### 6. Install NixOS

```bash
nixos-install --flake /tmp/homelab#workstation --no-root-password
```

Before reboot, restore the verified old SSH host key under `/mnt/etc/ssh/` if
that recovery path is approved. Otherwise, create the new key explicitly;
NixOS normally generates a missing host key during first boot, which is too
late for an independent fingerprint:

```bash
install -d -m 0755 /mnt/etc/ssh
test -e /mnt/etc/ssh/ssh_host_ed25519_key || \
  ssh-keygen -q -t ed25519 -N '' -f /mnt/etc/ssh/ssh_host_ed25519_key
ssh-keygen -lf /mnt/etc/ssh/ssh_host_ed25519_key.pub
ip -br address
reboot
```

Remove the installer media during restart. The `nori` account accepts only its
declared SSH keys; password login and root login are disabled. From a trusted
machine with this repository, derive the reserved LAN address and compare the
presented key fingerprint with the value recorded before reboot:

```bash
host="$(nix eval --raw .#lib.noriInventory.hosts.workstation.lanIp)"
ssh-keyscan -t ed25519 "$host" 2>/dev/null | ssh-keygen -lf -
ssh "nori@$host"
sudo whoami
```

If the address does not answer, inspect the router's DHCP leases using the
wired address recorded before reboot. Replace a stale `known_hosts` entry only
after the new fingerprint matches the recorded value. Do not depend on
Tailscale for first-boot access.

## Restore identity and state

If the old SSH host key was not restored, enroll the new age identity and
update only the required SOPS recipients. SOPS re-encryption is a separate
credential change and requires authorization.

Tailscale enrollment and any control-plane approval are also separate external
effects. Do not treat a successful NixOS boot as proof that either is complete.

Inspect Restic snapshots in a disposable restore directory before copying state
into the new system. Follow the root-drive runbook for service and user-data
recovery. Do not overwrite a running database with files from a snapshot.

## Acceptance

The installation is complete only after all applicable checks pass:

- the running system uses the approved revision;
- mounted filesystems match the reviewed source and physical disks;
- no preserved disk was formatted or mounted under the wrong role;
- SOPS-backed units can read only their declared secrets;
- operator SSH and local recovery access work;
- selected restored files and databases pass their own integrity checks;
- OneTouch backup and restore paths are re-established;
- `systemctl --failed` reports no unexpected failed units.

Record the installed revision, disk identities, restored snapshot IDs, checks,
and any boundary that remains unverified.
