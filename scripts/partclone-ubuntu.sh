#!/usr/bin/env bash
# nori-station Ubuntu filesystem-level backup.
#
# Replacement for dd-ubuntu.sh on this drive. The WD Black SN750 does not
# return zeros after TRIM, so a full-disk dd produces ~900+ GB of mostly
# random data that doesn't compress. partclone.ext4 reads only USED blocks
# of the ext4 root, sidestepping that problem entirely.
#
# Output (~30 GB compressed):
#   partition-table.sgdisk      GPT backup (sgdisk format)
#   partition-table.sfdisk      GPT dump (text, also restorable)
#   partition-table.lsblk       human reference
#   esp.img.zst                 raw dd of /dev/nvme0n1p1 (ESP, 1 GB)
#   root.partclone.zst          partclone of /dev/nvme0n1p2 (ext4 root)
#   manifest.txt + checksums.txt + RESTORE.md
#
# SAFETY: identifies source by model. Reads only — no writes to nvme0n1.
#
# Usage:
#   sudo scripts/partclone-ubuntu.sh [-y] <output-dir>
#
# Example:
#   sudo scripts/partclone-ubuntu.sh /media/OneTouch

set -o pipefail

SCRIPT_VERSION="1"
EXPECTED_HOSTNAME="nori-station"
TARGET_DEV="/dev/nvme0n1"
EXPECTED_MODEL_MATCH="WDS100T3X0C"
FORBIDDEN_MODEL_MATCH="Force MP510"
ESP_PART="${TARGET_DEV}p1"
ROOT_PART="${TARGET_DEV}p2"
ZSTD_LEVEL="3"
ZSTD_THREADS="0"

die()  { echo "error: $*" >&2; exit 1; }
note() { echo "[partclone-ubuntu] $*"; }
step() { echo; echo "=== $* ==="; }

# --- args ----------------------------------------------------------------

ASSUME_YES=0
OUT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *)  [[ -z "$OUT_ROOT" ]] || die "multiple output dirs given"
        OUT_ROOT="$1"; shift ;;
  esac
done

[[ -n "$OUT_ROOT" ]] || { echo "usage: sudo $0 [-y] <output-dir>" >&2; exit 2; }

# --- preflight -----------------------------------------------------------

[[ $EUID -eq 0 ]] || die "must run as root"

HOST="$(hostname)"
if [[ "$HOST" != "$EXPECTED_HOSTNAME" ]]; then
  echo "warning: hostname is '$HOST', expected '$EXPECTED_HOSTNAME'" >&2
  [[ $ASSUME_YES -eq 1 ]] || { read -r -p "continue? [y/N] " a; [[ "$a" =~ ^[yY]$ ]] || exit 1; }
fi

[[ -b "$TARGET_DEV" ]] || die "target not found: $TARGET_DEV"
[[ -b "$ESP_PART"   ]] || die "ESP partition not found: $ESP_PART"
[[ -b "$ROOT_PART"  ]] || die "root partition not found: $ROOT_PART"
[[ -d "$OUT_ROOT" && -w "$OUT_ROOT" ]] || die "output dir not writable: $OUT_ROOT"

for cmd in partclone.ext4 sgdisk sfdisk zstd dd numfmt sha256sum; do
  command -v "$cmd" >/dev/null \
    || die "missing tool: $cmd (apt install partclone gdisk util-linux zstd coreutils)"
done

# Identity guard.
TARGET_MODEL="$(lsblk -dn -o MODEL "$TARGET_DEV" | tr -s ' ' | xargs)"
note "target:        $TARGET_DEV"
note "target model:  $TARGET_MODEL"

[[ "$TARGET_MODEL" == *"$EXPECTED_MODEL_MATCH"* ]] \
  || die "target model does not contain '$EXPECTED_MODEL_MATCH' — refusing"
[[ "$TARGET_MODEL" == *"$FORBIDDEN_MODEL_MATCH"* ]] \
  && die "target model matches Windows disk — refusing"

# --- estimates -----------------------------------------------------------

ROOT_USED_KB="$(df -k "$ROOT_PART" 2>/dev/null | awk 'NR==2 {print $3}')"
ROOT_USED_BYTES=$(( ROOT_USED_KB * 1024 ))
ESP_BYTES="$(blockdev --getsize64 "$ESP_PART")"

# Budget: ext4 used + ESP raw + 20% headroom (partclone metadata, zstd dict).
BUDGET=$(( (ROOT_USED_BYTES + ESP_BYTES) * 12 / 10 ))
AVAIL_BYTES="$(df -B1 --output=avail "$OUT_ROOT" | tail -1 | tr -d ' ')"

note "ext4 used:     $(numfmt --to=iec --suffix=B "$ROOT_USED_BYTES")"
note "ESP raw size:  $(numfmt --to=iec --suffix=B "$ESP_BYTES")"
note "budget:        ~$(numfmt --to=iec --suffix=B "$BUDGET")"
note "available:     $(numfmt --to=iec --suffix=B "$AVAIL_BYTES")"

(( AVAIL_BYTES >= BUDGET )) || die "insufficient space at $OUT_ROOT"

# --- confirm -------------------------------------------------------------

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUT_ROOT/ubuntu-pc-$TS"

cat <<EOF

about to:
  read  $TARGET_DEV ($TARGET_MODEL)
  write $OUT/

      partition-table.{sgdisk,sfdisk,lsblk}
      esp.img.zst              ($(numfmt --to=iec --suffix=B "$ESP_BYTES") raw, expected ~10 MB compressed)
      root.partclone.zst       ($(numfmt --to=iec --suffix=B "$ROOT_USED_BYTES") used, expected ~25-35 GB compressed)

EOF

if (( ! ASSUME_YES )); then
  read -r -p "proceed? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { note "aborted"; exit 1; }
fi

mkdir -p "$OUT" || die "could not create $OUT"
ERR="$OUT/errors.log"
: > "$ERR"

# --- partition table -----------------------------------------------------

step "partition table"
sgdisk --backup="$OUT/partition-table.sgdisk" "$TARGET_DEV" 2>>"$ERR"
sfdisk --dump "$TARGET_DEV" > "$OUT/partition-table.sfdisk" 2>>"$ERR"
lsblk -f "$TARGET_DEV"      > "$OUT/partition-table.lsblk"  2>>"$ERR"

# --- ESP -----------------------------------------------------------------

step "ESP raw image"
START="$(date +%s)"
dd if="$ESP_PART" bs=4M status=progress 2>>"$ERR" \
  | zstd -T"$ZSTD_THREADS" -"$ZSTD_LEVEL" -o "$OUT/esp.img.zst"
ESP_ELAPSED=$(( $(date +%s) - START ))

# --- ext4 root -----------------------------------------------------------

step "ext4 root (partclone — used blocks only)"
START="$(date +%s)"
partclone.ext4 -c -s "$ROOT_PART" 2>>"$ERR" \
  | zstd -T"$ZSTD_THREADS" -"$ZSTD_LEVEL" -o "$OUT/root.partclone.zst"
ROOT_ELAPSED=$(( $(date +%s) - START ))

# --- verify --------------------------------------------------------------

step "verify"
note "zstd -t (archive integrity)"
zstd -t "$OUT/esp.img.zst"        || die "esp.img.zst is corrupt"
zstd -t "$OUT/root.partclone.zst" || die "root.partclone.zst is corrupt"

note "sha256sum (slow)"
( cd "$OUT" && sha256sum esp.img.zst root.partclone.zst partition-table.sgdisk \
    > checksums.txt )

# --- manifest + restore notes -------------------------------------------

ESP_SIZE="$(stat -c %s "$OUT/esp.img.zst")"
ROOT_SIZE="$(stat -c %s "$OUT/root.partclone.zst")"
TOTAL=$(( ESP_SIZE + ROOT_SIZE ))

cat > "$OUT/manifest.txt" <<EOF
nori Ubuntu filesystem-level backup
-----------------------------------
script:           partclone-ubuntu.sh v$SCRIPT_VERSION
timestamp (UTC):  $TS
host:             $HOST
source disk:      $TARGET_DEV ($TARGET_MODEL)

esp source:       $ESP_PART  ($(numfmt --to=iec --suffix=B "$ESP_BYTES") raw)
esp image:        $OUT/esp.img.zst  ($(numfmt --to=iec --suffix=B "$ESP_SIZE"))
esp elapsed:      ${ESP_ELAPSED}s

root source:      $ROOT_PART  ($(numfmt --to=iec --suffix=B "$ROOT_USED_BYTES") used)
root image:       $OUT/root.partclone.zst  ($(numfmt --to=iec --suffix=B "$ROOT_SIZE"))
root elapsed:     ${ROOT_ELAPSED}s

total compressed: $(numfmt --to=iec --suffix=B "$TOTAL")
EOF

cat > "$OUT/RESTORE.md" <<'RESTORE_EOF'
# Restoring this Ubuntu backup

Filesystem-aware partial restore. Recreates the partition table, writes
back the ESP raw, restores the ext4 root via partclone, and reinstalls
GRUB so UEFI finds the system.

## Required tools (live USB)

`partclone`, `sgdisk`, `zstd`, `dd`. SystemRescue and Clonezilla include
all four; Ubuntu Live needs `apt install partclone gdisk zstd`.

## Verify before touching anything

    cd /mnt/onetouch/ubuntu-pc-<TIMESTAMP>
    sha256sum -c checksums.txt
    zstd -t esp.img.zst root.partclone.zst

## Confirm the target disk

    lsblk -dn -o NAME,SIZE,MODEL
    # Restore target must contain "WDS100T3X0C" in MODEL.
    # NEVER restore to a disk whose MODEL contains "Force MP510" — that
    # is the Windows disk and would be silently overwritten.

## Restore (DESTRUCTIVE — wipes the entire target disk)

    # 1. Partition table
    sgdisk --load-backup=partition-table.sgdisk /dev/nvme0n1
    partprobe /dev/nvme0n1

    # 2. ESP (raw)
    zstd -d -c esp.img.zst | dd of=/dev/nvme0n1p1 bs=4M status=progress
    sync

    # 3. ext4 root (partclone)
    zstd -d -c root.partclone.zst | partclone.ext4 -r -s - -o /dev/nvme0n1p2
    sync

    # 4. Reinstall GRUB so UEFI finds Ubuntu
    mount /dev/nvme0n1p2 /mnt
    mount /dev/nvme0n1p1 /mnt/boot/efi
    for d in dev dev/pts proc sys run; do mount --rbind /$d /mnt/$d; done
    chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu
    chroot /mnt update-grub
    umount -R /mnt

Reboot. UEFI boot menu should show "ubuntu" again.

## Notes

- partclone preserves the ext4 UUID, so `/etc/fstab` continues to work
  unchanged after restore. Same for the ESP UUID via raw dd.
- Target disk must be the same size or larger than the source (1 TB).
- This restore does not touch nvme1n1 (Windows), sda (IronWolf), or sdb
  (One Touch).
RESTORE_EOF

# --- summary -------------------------------------------------------------

step "done"
note "output:    $OUT"
note "esp:       $(numfmt --to=iec --suffix=B "$ESP_SIZE") (in ${ESP_ELAPSED}s)"
note "root:      $(numfmt --to=iec --suffix=B "$ROOT_SIZE") (in ${ROOT_ELAPSED}s)"
note "total:     $(numfmt --to=iec --suffix=B "$TOTAL")"
note "restore:   $OUT/RESTORE.md"
