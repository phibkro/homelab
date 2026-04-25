# Phase 4: NixOS install on nori-station (disko-based)

Bare-metal install. The flake's `hosts/nori-station/disko.nix` declares
the partition layout; disko applies it; `nixos-install` writes the
system. No manual `parted` or `mkfs` — the layout is in version control.

Read this whole document before starting. It assumes Phase 3 succeeded
and both backups (rsync + partclone) are on One Touch and verified.

## 1. Prepare the USB installer

On your Mac:

```bash
diskutil list
# Find your USB stick — typically /dev/diskN where N >= 2.
# Verify by SIZE; do NOT pick the Mac's internal disk.

diskutil unmountDisk /dev/diskN

# Use the raw device (rdiskN) for ~5x faster writes.
sudo dd if=~/Downloads/nixos-minimal-25.11.<...>.iso \
        of=/dev/rdiskN \
        bs=1m \
        status=progress

sudo diskutil eject /dev/diskN
```

Pull the USB out.

## 2. Stage physically

- Plug USB into nori-station.
- Connect keyboard + monitor.
- **Disconnect One Touch** (we don't want it on the USB bus during
  install — reduces accidents).

## 3. Boot from USB

Power on. Spam **F12** at the Gigabyte splash to enter the boot menu.
Pick the **UEFI** entry for the USB (not the legacy/BIOS entry).

NixOS boot menu appears → press Enter on the default. Land at a TTY
prompt. (Minimal ISO has no GUI; that's fine.)

```
sudo -i
```

You're root in the installer.

## 4. Verify network and identify disks

```
ping -c 2 cache.nixos.org
lsblk -o NAME,SIZE,MODEL,TYPE
```

Confirm:
- `nvme0n1` is `WDS100T3X0C-00SJG0` (WD Black SN750, 931.5 GB) — install
  target.
- `nvme1n1` is `Force MP510` (Corsair, 894 GB) — Windows. **Do not
  touch.**
- `sda` is the IronWolf Pro (3.6 TB) — leave it alone for Phase 4; Phase
  2 reformats it later.

If any disk is missing or the model strings don't match, **stop** and
investigate. The disko config is hardcoded for `/dev/nvme0n1`.

## 5. Run disko

The installer ships with `nix` and flake support. Apply the partition
layout from the flake:

```
nix-shell -p git
git clone https://github.com/phibkro/homelab.git /tmp/homelab
cd /tmp/homelab

nix --experimental-features 'nix-command flakes' \
    run github:nix-community/disko/latest -- \
    --mode disko --flake /tmp/homelab#nori-station
```

What this does:
- Wipes and re-partitions `/dev/nvme0n1` per `hosts/nori-station/disko.nix`.
- Creates the ESP (vfat, label `BOOT`) and btrfs filesystem (label
  `nixos`) with six subvolumes.
- Mounts everything under `/mnt/` ready for `nixos-install`.

Disko prompts before destructive operations. **It will not touch
`nvme1n1`** — the disko config names `nvme0n1` explicitly.

When it finishes, sanity-check the result:

```
findmnt -R /mnt
```

Expect six btrfs mounts (`/`, `/home`, `/nix`, `/var/lib`, `/srv/share`,
`/.snapshots`) and one vfat mount (`/boot`), all under `/mnt`.

## 6. Install

```
nixos-install --flake /tmp/homelab#nori-station --no-root-password
```

Expected runtime: 5–15 min. You'll see `copying path '/nix/store/...'`
streams, then activation. At the end: `installation finished!`

The `nori` user is created **without a password**. SSH will work via the
Mac's key; `sudo` doesn't need a password (`wheelNeedsPassword = false`).

### If install errors

Most likely culprits:
- **Driver build failure** (`nvidiaPackages.production` resolves to
  580.119.02 + kernel 6.19): fall back to `beta` or pin
  `linuxPackages_6_18`. See `docs/DESIGN.md` L101–106.
- **`nixos-hardware.nixosModules.common-pc-ssd` missing**: drop the
  import.

For any error: paste the message, edit the flake on the laptop, push,
`git pull` in the installer, retry.

## 7. Capture the lock file

Disko + nixos-install just generated `/tmp/homelab/flake.lock` as a
side effect. Pull it back to the canonical repo so future installs are
reproducible.

From a second Mac terminal (with the installer still running on
nori-station, on the LAN — find its IP via `ip -br addr` in the
installer):

```bash
scp nixos@<installer-ip>:/tmp/homelab/flake.lock \
    /Users/nori/Documents/nix-migration/flake.lock

cd /Users/nori/Documents/nix-migration
git add flake.lock
git commit -m "chore: pin flake.lock from first nori-station install"
git push
```

(The installer's `nixos` user has password `nixos`.)

If you forget this step before reboot, no big deal — we can pull the
lock from nori-station via SSH after first boot.

## 8. Reboot

```
reboot
```

Pull the USB out as the machine restarts. UEFI's first boot entry is
"Linux Boot Manager" (created by `bootctl` during install); the system
should boot straight into NixOS, landing at a TTY login prompt:

```
nori-station login:
```

Login as `nori` (no password). You're in.

## 9. Validate from the Mac

Find the LAN IP. Either check your router's DHCP leases or, on
nori-station console, `ip -br addr`.

```bash
ssh nori@192.168.1.<NEW>          # SSH key, no password
sudo whoami                        # → root, no password
sudo tailscale up --ssh            # browser auth, joins tailnet
tailscale status                   # confirm joined
```

Phase 4 is done when all four work.

## What this install does NOT do (deferred)

- **`flake.lock` capture and commit** — see step 7. Easy to miss.
- **Service migration.** Tailscale is up by virtue of `services.tailscale`
  in `common.nix`, but Samba, Ollama, Jellyfin, Immich, etc. are Phase 5.
- **Tailscale identity restore.** Fresh `tailscale up` registers a *new*
  node. The old `nori-station` from Ubuntu lingers as expired in the
  admin console. Either delete it now or restore `/var/lib/tailscale/`
  from the rsync backup before starting tailscaled (Phase 5).
- **IronWolf Pro reformat.** Phase 2. Separate operation; runs when
  you have a free evening.
- **Pi setup.** Phase 5. nori-pi as DNS/backup target is described in
  `docs/DESIGN.md` but not yet implemented in the flake.

## What to do if it goes catastrophically wrong

You have full Ubuntu rollback available from the partclone backup at
`/media/OneTouch/ubuntu-pc-20260425T000045Z/`. Procedure in that
directory's `RESTORE.md`. Worst case: 30–60 min of restore, you're
back on Ubuntu.
