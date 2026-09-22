# Root drive failure

**Recovery target**: <1 day for rebuild. OneTouch backup policy is enabled, but
state recovery depends on the disk surviving and on verified usable snapshots.

## Symptom

The WD Black SN750 NVMe (NixOS root) is dead, dying, or otherwise unrecoverable. Identifying signs:

- Boot fails to mount root; recovery shell shows ATA/NVMe errors.
- SMART says PASS but read errors flood `dmesg`.
- Drive doesn't enumerate at all.

## Decision tree

1. **Drive replaceable in-place?** New SN750 (or equivalent) → continue below.
2. **Need to relocate to a different machine?** Same flake, different hardware — adjust `hardware.nix` first, then continue.

## Procedure

### 0. Preserve the other disks

The MP510 is the other SSD and contains preserved historical archives; its
old Windows label is stale. Preserve MP510, the cold IronWolf Pro, and any
connected OneTouch. Match model and serial to stable by-id paths before an
explicitly approved partition operation. Inspect the evaluated disko scope;
it must contain only the replacement root disk.

### 1. Boot the NixOS minimal installer USB

Latest unstable installer ISO on a USB stick. Boot. Network up (ethernet or `iwctl` for wifi).

### 2. SSH in (faster than typing on tty)

```bash
# In the installer:
sudo passwd nixos    # set a password so you can ssh
ip a                 # find the LAN IP
```

From your laptop:

```bash
ssh nixos@<lan-ip>
```

### 3. Clone the flake

```bash
nix-shell -p git
git clone https://github.com/phibkro/homelab /tmp/homelab
cd /tmp/homelab
```

### 4. Run disko

```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest -- \
  --mode disko infra/workstation/disko.nix
```

This wipes the new root drive (by-id pinned to whatever the new SN750's serial is — **edit `infra/workstation/disko.nix` first if the serial changed**) and creates the six-subvolume btrfs layout.

### 5. Install

```bash
sudo nixos-install --flake /tmp/homelab#workstation --no-root-password
```

After installation succeeds, reboot into the installed system.

### 6. First boot — recover sops

The age key for sops decryption is derived from the host's SSH key. Fresh install = new SSH key = secrets won't decrypt.

Two paths:

- **You backed up the old `/etc/ssh/ssh_host_ed25519_key`** before the failure: place it at `/etc/ssh/ssh_host_ed25519_key` on the new install. Reboot. sops works again.
- **You didn't back up the key**: re-key SOPS. Boot into a minimally functional system, derive the new age recipient with `ssh-to-age`, update only the workstation recipient rules in `.sops.yaml`, and run `sops updatekeys secrets/workstation-runtime.yaml` and `sops updatekeys secrets/network.yaml` from an enrolled recovery identity.

Preserve any existing recovery key securely. Re-encryption is a separate
approved credential operation; do not assume a key backup exists.

### 7. Restore state from restic

The new install has empty service and user state. Verify the existing MP510
mount at `/mnt/backup-local` and inspect repository snapshots before restoring.
Inspect the OneTouch destination declared in `inventory/backup.nix` as well;
verify its identity and usable snapshots before selecting a repository.
Do not assume a new install has materialized backup credentials. Use a
protected recovery credential file obtained through its authorized provider.
Stop affected services and inspect snapshot paths before writing restored data.

```text
sudo restic -r /mnt/backup-local/<repo> --password-file <protected-credential-file> snapshots
sudo restic -r /mnt/backup-local/<repo> --password-file <protected-credential-file> restore <snapshot-id> --target <disposable-directory>
```

Validate the restored files, then copy the selected state into its intended
location while affected services remain stopped. Follow database-specific
restore procedures for logical dumps; do not overwrite a running database.

Historical repository names below are inspection leads, not verified coverage.
List snapshots and inspect their contents before selecting a restore:

| Repo | Why early |
|---|---|
| `user-data` | `/home/nori`, `/srv/share`, `/srv/nori`, agent state, secrets/age |
| `media-irreplaceable` | Observed directory was only approximately 40 KiB; no usable media snapshots verified |
| `vaultwarden`, `immich`, etc. | Inspect for actual service state and consistent dumps |

If MP510 is unavailable, inspect the independent OneTouch repositories after
verifying the disk identity, credentials, and snapshots. If OneTouch is also
unavailable, only preserved historical archives remain; there is no off-site
backup target. Do not assume `restic recover` repairs unreadable data: it
recovers unreferenced snapshots, not damaged disk blocks.

### 8. Re-import IronWolf media

IronWolf is a separate cold-data drive and may survive an isolated SN750 failure; inspect its health and contents. After install, the disko config in `disko-media.nix` recognizes the existing filesystem; `nixos-rebuild switch` mounts it without reformatting. **Do NOT re-run disko on the IronWolf** — that wipes it.

### 9. Verify recovery and record gaps

Verify mounted disk identities, restored file contents, database validity,
service health, and operator access. Record the snapshot IDs actually used and
any missing state. Retained local btrfs snapshots and application dumps help
with logical failures but do not provide independent disk-loss protection.

Use the [OneTouch cutover runbook](onetouch-backup-cutover.md) to re-establish
connection, destination identity, and the backup/restore journey after recovery;
no timer-check result substitutes for that evidence.

## Don't forget

- Tailscale state may need re-enrollment if no usable state copy exists.
  Re-enrollment and external approval remain explicit operator actions.
- Pi owns the HTTPS entry plane through Ansible. Rebuilding workstation does
  not restore Pi's certificate, authentication, or network state; use the
  [Pi failure runbook](pi-failure.md) when that appliance is also affected.
