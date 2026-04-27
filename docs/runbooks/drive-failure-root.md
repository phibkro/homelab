# Root drive failure

**RTO**: <1 day. Bare metal rebuild from flake + restic restore of state.

## Symptom

The WD Black SN750 NVMe (NixOS root) is dead, dying, or otherwise unrecoverable. Identifying signs:

- Boot fails to mount root; recovery shell shows ATA/NVMe errors.
- SMART says PASS but read errors flood `dmesg`.
- Drive doesn't enumerate at all.

## Decision tree

1. **Drive replaceable in-place?** New SN750 (or equivalent) → continue below.
2. **Need to relocate to a different machine?** Same flake, different hardware — adjust `hardware.nix` first, then continue.

## Procedure

### 0. Verify Windows drive is untouched

The Corsair MP510 (Windows) is on a different NVMe slot. Disko configs are by-id-pinned to prevent target confusion. **Re-read `docs/gotchas.md` "NVMe `/dev` enumeration is unstable"** before any partition operation.

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
  --mode disko hosts/nori-station/disko.nix
```

This wipes the new root drive (by-id pinned to whatever the new SN750's serial is — **edit `hosts/nori-station/disko.nix` first if the serial changed**) and creates the six-subvolume btrfs layout.

### 5. Install

```bash
sudo nixos-install --flake /tmp/homelab#nori-station --no-root-password
```

Reboots into the freshly-installed system.

### 6. First boot — recover sops

The age key for sops decryption is derived from the host's SSH key. Fresh install = new SSH key = secrets won't decrypt.

Two paths:

- **You backed up the old `/etc/ssh/ssh_host_ed25519_key`** before the failure: place it at `/etc/ssh/ssh_host_ed25519_key` on the new install. Reboot. sops works again.
- **You didn't back up the key**: re-key sops. Boot into a barely-functional system (services that need secrets will fail), generate the new pubkey via `ssh-to-age`, edit `.sops.yaml` and re-encrypt `secrets/secrets.yaml` from another host that has the existing age key.

The first path is preferred. Add the SSH host key to your "irreplaceable" backup tier going forward — it's tiny and prevents a real recovery hassle.

### 7. Restore state from restic

The new install has empty `/var/lib`, empty `/home`, etc. Restore from whichever restic repository is closest:

```bash
# Local fast restore (OneTouch, attached at /mnt/backup):
sudo restic -r /mnt/backup/user-data \
  --password-file /run/secrets/restic-password \
  restore latest --target /

sudo restic -r /mnt/backup/media-irreplaceable \
  --password-file /run/secrets/restic-password \
  restore latest --target /

sudo restic -r /mnt/backup/open-webui \
  --password-file /run/secrets/restic-password \
  restore latest --target /
```

If `/mnt/backup` (OneTouch) also failed, fall back to:
- `nori-pi:/mnt/backup/...` (when the Pi exists)
- `sftp:u123@u123.your-storagebox.de:<name>` (Hetzner off-site, when configured)

### 8. Re-import IronWolf media

The IronWolf is on a different drive — its data survives an SN750 failure. After install, the disko config in `disko-media.nix` recognizes the existing filesystem; `nixos-rebuild switch` mounts it without reformatting. **Do NOT re-run disko on the IronWolf** — that wipes it.

### 9. Verify the safety net

```bash
sudo systemctl list-timers 'restic-*' 'btrbk-*'
sudo restic -r /mnt/backup/user-data --password-file /run/secrets/restic-password snapshots
sudo systemctl start restic-check-weekly.service
```

All green = recovery complete.

## Don't forget

- The Caddy CA cert is committed at `modules/server/caddy-local-ca.crt`. After install, downstream devices that trusted the OLD CA (Mac keychain, Firefox cert store, etc.) **will reject the new CA** until you re-import. Plan for this — it'll feel like "the homelab broke" after a recovery.
- Tailscale state is in `/var/lib/tailscale`. Restored from restic. If that doesn't work, run `sudo tailscale up` on the new host and approve in the admin console.
