#!/usr/bin/env bash
# Phase 3 VM install: partition, format, mount.
#
# Run inside the NixOS graphical installer as root, BEFORE nixos-install.
# Destructive: wipes the target disk and creates the btrfs-on-nvme layout
# the flake's hardware.nix expects (labels "BOOT" and "nixos", four
# subvolumes @, @home, @nix, @snapshots with compress=zstd:3,noatime).
#
# Usage:
#   curl -L https://raw.githubusercontent.com/phibkro/homelab/main/scripts/vm-install-setup.sh | bash
#   # or, to target a disk other than /dev/sda:
#   curl -L ... | bash -s /dev/vda

set -euo pipefail

DISK="${1:-/dev/sda}"

echo "[vm-setup] target disk: $DISK"
lsblk "$DISK" || { echo "no such disk"; exit 1; }
echo
read -rp "this will WIPE $DISK. type 'yes' to proceed: " confirm
[[ "$confirm" == "yes" ]] || { echo "aborted"; exit 1; }

# --- partition -----------------------------------------------------------

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 513MiB 100%

# Let the kernel re-read the partition table before we format.
partprobe "$DISK" || true
sleep 1

# --- format --------------------------------------------------------------

mkfs.vfat -n BOOT "${DISK}1"
mkfs.btrfs -f -L nixos "${DISK}2"

# --- subvolumes ----------------------------------------------------------

mount "${DISK}2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@snapshots
umount /mnt

# --- mount ---------------------------------------------------------------

MOPTS="compress=zstd:3,noatime"
mount -o "subvol=@,$MOPTS"          "${DISK}2" /mnt
mkdir -p /mnt/home /mnt/nix /mnt/.snapshots /mnt/boot
mount -o "subvol=@home,$MOPTS"      "${DISK}2" /mnt/home
mount -o "subvol=@nix,$MOPTS"       "${DISK}2" /mnt/nix
mount -o "subvol=@snapshots,$MOPTS" "${DISK}2" /mnt/.snapshots
mount "${DISK}1" /mnt/boot

# --- report --------------------------------------------------------------

echo
echo "[vm-setup] mounts:"
findmnt -R /mnt
echo
echo "[vm-setup] ready for: nixos-install --flake .#vm-test"
