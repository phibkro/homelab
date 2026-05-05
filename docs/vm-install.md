# Phase 3: NixOS VM dry-run install

Validates the install pipeline against the flake before touching workstation.

## 1. Create the VM in UTM

- **Architecture:** x86_64. On Intel Mac: **Virtualize** (native speed via
  Apple HVF). On Apple Silicon: Emulate (slow but correct).
- **System:** QEMU 9, standard. Enable UEFI boot.
- **CPU cores:** 4. **RAM:** 4 GB. **Disk:** 40 GB (VirtIO).
- **CD/DVD:** attach the NixOS minimal ISO.
- **Network:** Shared or Bridged — both work; Shared is simplest.

Boot. You land at a `nixos@nixos` shell.

## 2. Network + become root

    sudo -i
    ping -c 2 cache.nixos.org          # confirm internet
    ip -br addr                         # note the guest IP

## 3. Partition the disk

The VirtIO disk appears as `/dev/vda`. **Verify** with `lsblk` before the next
step — no other disks should be present.

    parted /dev/vda -- mklabel gpt
    parted /dev/vda -- mkpart ESP fat32 1MiB 513MiB
    parted /dev/vda -- set 1 esp on
    parted /dev/vda -- mkpart primary 513MiB 100%

Labels (critical — the flake mounts by label, not UUID):

    mkfs.vfat -n BOOT /dev/vda1
    mkfs.btrfs -L nixos /dev/vda2

## 4. Create btrfs subvolumes

    mount /dev/vda2 /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@nix
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

## 5. Mount with the install-time options

    MOPTS="compress=zstd:3,noatime"
    mount -o subvol=@,$MOPTS          /dev/vda2 /mnt
    mkdir -p /mnt/{home,nix,.snapshots,boot}
    mount -o subvol=@home,$MOPTS      /dev/vda2 /mnt/home
    mount -o subvol=@nix,$MOPTS       /dev/vda2 /mnt/nix
    mount -o subvol=@snapshots,$MOPTS /dev/vda2 /mnt/.snapshots
    mount /dev/vda1 /mnt/boot

Sanity check:

    findmnt -R /mnt

Expect one line per mount with `btrfs` on /, /home, /nix, /.snapshots and
`vfat` on /boot.

## 6. Fetch the flake

The installer ISO has `nix` with flake support enabled.

    nix-shell -p git
    cd /tmp
    git clone https://github.com/phibkro/homelab.git
    cd homelab

## 7. Install

    nixos-install --flake .#vm-test --no-root-password

`--no-root-password` leaves root with `!` (no password); you'll log in as
`nori` via SSH key. If the install fails during evaluation, the error points
at the specific file — fix, commit, push, `git pull`, retry.

When prompted at the end, set a password for the `nori` user. This is what
you'll type for `sudo` later.

## 8. Reboot into the installed system

    reboot

Eject the ISO in UTM when the VM powers off (CD/DVD → Clear). Power back on.

## 9. Verify from the Mac

On the VM console, log in as `nori` (password you just set). Get its IP:

    ip -br addr

From your Mac:

    ssh nori@<vm-ip>              # should succeed via key, no password prompt
    sudo tailscale up --ssh       # one-time auth, opens browser URL
    tailscale status              # confirm it appears on the tailnet

You're in. Reboot once more to confirm the system comes back clean — if
btrfs subvol mounts survive a reboot, the layout is correct.

## Expected outcome

If all of the above works, the flake is valid, the btrfs + systemd-boot
layout is right, and the install procedure is exactly what we'll run on
workstation. Phase 3 done.

## What to report

- Any step that errored (and the error text)
- The output of `findmnt -R /` after the final reboot
- Confirmation that `ssh nori@<vm-ip>` works from your Mac without a password
