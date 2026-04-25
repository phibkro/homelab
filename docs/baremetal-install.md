# Phase 4: NixOS install on nori-station

Bare-metal install. Mirrors Phase 3 (VM dry-run) — same flake, same partition
layout, same install command pattern. The difference is that this is the
real machine, with its real GPU and real network.

Read this whole document before starting. It assumes Phase 3 succeeded and
both backups (rsync + partclone) are in place on One Touch.

## 1. Prepare the USB installer

On your Mac:

```bash
diskutil list
# Find your USB stick — typically /dev/diskN where N >= 2.
# Verify by SIZE and the absence of "internal" — confusing it with the
# Mac's internal disk would brick your laptop.

diskutil unmountDisk /dev/diskN

# Use the raw device (rdiskN) for ~5x faster writes.
sudo dd if=~/Downloads/nixos-graphical-25.11.<...>.iso \
        of=/dev/rdiskN \
        bs=1m \
        status=progress

sudo diskutil eject /dev/diskN
```

Pull the USB out.

## 2. Boot nori-station from USB

1. Plug the USB into nori-station.
2. Connect a keyboard and monitor (you'll need them through the install).
3. Power on. Spam **F12** at the Gigabyte splash to enter the boot menu.
   (Other Gigabyte boards: F8 or F11 — try F12 first.)
4. Select the USB stick (often listed as "UEFI: <USB brand>"). **Pick the
   UEFI entry**, not the legacy/BIOS entry — without UEFI, systemd-boot
   won't install correctly.
5. NixOS boot menu appears → press Enter on the default.
6. GNOME desktop loads. Open Terminal, `sudo -i`.

## 3. Verify network and target disk

In the installer terminal:

```
ping -c 2 cache.nixos.org    # should succeed
lsblk -o NAME,SIZE,MODEL,TYPE
```

Confirm that:
- `nvme0n1` is `WDS100T3X0C-00SJG0` (931.5 GB) — your install target.
- `nvme1n1` is `Force MP510` (894 GB) — Windows. **Do not touch.**
- `sda` is the IronWolf Pro (3.6 TB).
- `sdb` is the One Touch (4.5 TB) — should appear if connected.

If any of those are missing or mismatched, **stop** and tell me. The
install scripts identify the disk by model and refuse to write to the
wrong one, but a missing disk is its own problem.

## 4. Run the partition setup script

```
curl -L https://raw.githubusercontent.com/phibkro/homelab/main/scripts/baremetal-install-setup.sh | bash
```

Type `yes` at the confirmation. Expected `findmnt -R /mnt` output: five
mounts on btrfs (root, home, nix, .snapshots) and vfat (boot). Same as
Phase 3.

## 5. Clone the flake locally and install

```
nix-shell -p git --run 'git clone https://github.com/phibkro/homelab.git /tmp/homelab'
cd /tmp/homelab
nixos-install --flake .#nori-station --no-root-password
```

Expected runtime: 5–15 min (depending on cache.nixos.org speed). At the
end you'll see "installation finished!" and the `nori` user will be
created **without a password** — that's fine because:

- `wheelNeedsPassword = false` is set, so `sudo` doesn't need one.
- SSH is key-only and the Mac's key is preauthorised.
- TTY login won't work until you `sudo passwd nori` later (rarely
  needed on a headless server).

If install errors, paste the message and we iterate.

## 6. Capture the lock file

The install side-effect was to create `/tmp/homelab/flake.lock`. Grab it
back to your Mac so it gets committed to the repo for future reproducible
builds:

```
# from another Mac terminal, after install completes but BEFORE reboot:
scp nixos@<installer-LAN-ip>:/tmp/homelab/flake.lock \
    /Users/nori/Documents/nix-migration/flake.lock
```

(The installer's `nixos` user has password `nixos` and is reachable over
LAN.) Then on your Mac, `cd /Users/nori/Documents/nix-migration && git add
flake.lock && git commit -m "chore: pin flake inputs from first install"
&& git push`.

If you forget this step, no big deal — we can grab the lock from
nori-station after first boot via SSH.

## 7. Reboot

In the installer:

```
reboot
```

Pull the USB out as the machine restarts. UEFI's first boot entry should
now be "Linux Boot Manager" (created by `bootctl` during install), and
the system should boot straight into NixOS.

If you see "no bootable device" instead — same UTM-style fix:
1. Boot the USB again.
2. In the installer, mount and run `bootctl install` (procedure in
   `docs/vm-install.md` step 4 from the troubleshooting section).
3. Reboot.

This shouldn't happen on real hardware — UEFI NVRAM persists properly —
but the recovery path is the same.

## 8. Validate from the Mac

Find nori-station's LAN IP. From the inventory it was `192.168.1.181` via
DHCP, but DHCP can hand it a different one. Either:

- Check your router's DHCP leases.
- Or boot it, plug in the monitor briefly, run `ip -br addr`, note the IP,
  unplug.

Then:

```bash
ssh nori@192.168.1.<NEW>          # SSH key, no password
sudo systemctl status sshd        # passwordless sudo
sudo tailscale up --ssh            # browser auth
tailscale status                   # confirm joined tailnet
```

When all three work, Phase 4 is done. nori-station is on NixOS, reachable
over your tailnet, and ready for service migration in Phase 5.

## What this install does NOT do (deferred)

- **Service migration.** Tailscale, Samba, Ollama, Jellyfin, etc. all
  come up in Phase 5 as we wire the pillar modules.
- **Restore Tailscale identity.** A fresh `tailscale up` registers a
  *new* node on your tailnet. The old "nori-station" entry from Ubuntu
  will linger as expired. Either delete it from the admin console or, in
  Phase 5, restore `/var/lib/tailscale/` from the rsync backup before
  starting tailscaled.
- **IronWolf Pro reformat.** Phase 2 (btrfs reformat of `/dev/sda`) is
  separate and runs independently when you have a free evening.

## What to do if it goes catastrophically wrong

You have full Ubuntu rollback:
1. Boot a SystemRescue / Clonezilla USB.
2. Mount One Touch.
3. Follow `RESTORE.md` inside the most recent `ubuntu-pc-*/` directory.

Worst case: you spend 30–60 min restoring Ubuntu from the partclone
image, and you're back where you started. You don't lose data.
