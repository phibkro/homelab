#!/usr/bin/env bash
# Phase 4 bare-metal install: partition, format, mount nori-station's NVMe.
#
# Same on-disk layout as the VM dry-run (btrfs labels "nixos" + "BOOT",
# four subvolumes @, @home, @nix, @snapshots, compress=zstd:3,noatime).
# The flake's hardware.nix mounts by label, so this layout is portable.
#
# Refuses to run unless the target disk's model contains "WDS100T3X0C"
# (the WD Black SN750), AND refuses if it matches "Force MP510" (the
# Windows disk). There is no path by which it writes to nvme1n1.
#
# Usage (run inside the NixOS installer as root):
#   curl -L https://raw.githubusercontent.com/phibkro/homelab/main/scripts/baremetal-install-setup.sh | bash
#   # or to override the target disk (rare):
#   curl -L ... | bash -s /dev/nvme0n1

set -euo pipefail

DISK="${1:-/dev/nvme0n1}"
EXPECTED_MODEL_MATCH="WDS100T3X0C"
FORBIDDEN_MODEL_MATCH="Force MP510"

# NVMe and mmcblk devices use a "p" infix between disk and partition number.
if [[ "$DISK" == *"nvme"* || "$DISK" == *"mmcblk"* ]]; then
  P="p"
else
  P=""
fi
ESP_PART="${DISK}${P}1"
ROOT_PART="${DISK}${P}2"

echo "[bm-setup] target disk: $DISK"

# --- identity guard ------------------------------------------------------

[[ -b "$DISK" ]] || { echo "no such disk: $DISK"; exit 1; }
MODEL="$(lsblk -dn -o MODEL "$DISK" | tr -s ' ' | xargs)"
echo "[bm-setup] target model: $MODEL"

[[ "$MODEL" == *"$EXPECTED_MODEL_MATCH"* ]] \
  || { echo "[bm-setup] model does not contain '$EXPECTED_MODEL_MATCH' — refusing"; exit 1; }
[[ "$MODEL" == *"$FORBIDDEN_MODEL_MATCH"* ]] \
  && { echo "[bm-setup] model matches Windows disk — refusing"; exit 1; }

lsblk "$DISK"
echo
read -rp "this will WIPE $DISK. type 'yes' to proceed: " confirm
[[ "$confirm" == "yes" ]] || { echo "aborted"; exit 1; }

# --- partition -----------------------------------------------------------

# Wipe existing signatures so parted doesn't complain about overlapping FS.
wipefs -a "$DISK"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB     # 1 GiB ESP
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 1025MiB 100%

partprobe "$DISK" || true
sleep 1

# --- format --------------------------------------------------------------

mkfs.vfat -n BOOT "$ESP_PART"
mkfs.btrfs -f -L nixos "$ROOT_PART"

# --- subvolumes ----------------------------------------------------------

mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@snapshots
umount /mnt

# --- mount ---------------------------------------------------------------

MOPTS="compress=zstd:3,noatime"
mount -o "subvol=@,$MOPTS"          "$ROOT_PART" /mnt
mkdir -p /mnt/home /mnt/nix /mnt/.snapshots /mnt/boot
mount -o "subvol=@home,$MOPTS"      "$ROOT_PART" /mnt/home
mount -o "subvol=@nix,$MOPTS"       "$ROOT_PART" /mnt/nix
mount -o "subvol=@snapshots,$MOPTS" "$ROOT_PART" /mnt/.snapshots
mount "$ESP_PART" /mnt/boot

# --- report --------------------------------------------------------------

echo
echo "[bm-setup] mounts:"
findmnt -R /mnt
echo
echo "[bm-setup] ready for: nixos-install --flake .#nori-station --no-root-password"
