#!/usr/bin/env bash
# nori-station Ubuntu full-disk image (compressed).
#
# Streams a block-level image of the Ubuntu disk (/dev/nvme0n1) through
# zstd to a timestamped directory on an external drive. The resulting
# archive is a true byte-for-byte snapshot that can restore the entire
# Ubuntu install with a single dd-on-restore.
#
# SAFETY: this script identifies the target disk by model string
# (WDS100T3X0C), not by /dev node. It refuses to run if the expected
# device isn't present or the model doesn't match, so there is no path
# by which it will read from nvme1n1 (Windows).
#
# The image is taken with the filesystem live. ext4 handles this gracefully
# on restore (journal replay + fsck), but for a fully-quiescent image you
# would boot a live USB and run the same commands against the offline disk.
#
# Usage:
#   sudo scripts/dd-ubuntu.sh [-y] <output-dir>
#
# Example:
#   sudo scripts/dd-ubuntu.sh /media/OneTouch

set -o pipefail

SCRIPT_VERSION="1"
EXPECTED_HOSTNAME="nori-station"
TARGET_DEV="/dev/nvme0n1"
EXPECTED_MODEL_MATCH="WDS100T3X0C"   # WD Black SN750 — Ubuntu disk
FORBIDDEN_MODEL_MATCH="Force MP510"   # Corsair — Windows disk, double-check
ZSTD_LEVEL="3"
ZSTD_THREADS="0"   # 0 = use all cores

die()  { echo "error: $*" >&2; exit 1; }
note() { echo "[dd-ubuntu] $*"; }
step() { echo; echo "=== $* ==="; }

# --- args ----------------------------------------------------------------

ASSUME_YES=0
OUT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y)       ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)       die "unknown flag: $1" ;;
    *)        [[ -z "$OUT_ROOT" ]] || die "multiple output dirs given"
              OUT_ROOT="$1"; shift ;;
  esac
done

[[ -n "$OUT_ROOT" ]] || { echo "usage: sudo $0 [-y] <output-dir>" >&2; exit 2; }

# --- preflight -----------------------------------------------------------

[[ $EUID -eq 0 ]] || die "must run as root (sudo)"

HOST="$(hostname)"
if [[ "$HOST" != "$EXPECTED_HOSTNAME" ]]; then
  echo "warning: hostname is '$HOST', expected '$EXPECTED_HOSTNAME'" >&2
  [[ $ASSUME_YES -eq 1 ]] || { read -r -p "continue anyway? [y/N] " a; [[ "$a" =~ ^[yY]$ ]] || exit 1; }
fi

[[ -b "$TARGET_DEV" ]] || die "target device not found: $TARGET_DEV"
[[ -d "$OUT_ROOT" ]]   || die "output dir does not exist: $OUT_ROOT"
[[ -w "$OUT_ROOT" ]]   || die "output dir not writable: $OUT_ROOT"

command -v zstd >/dev/null    || die "zstd not installed"
command -v sha256sum >/dev/null || die "sha256sum not installed"

# --- identity checks -----------------------------------------------------
# Guard against any chance of imaging the wrong disk.

TARGET_MODEL="$(lsblk -dn -o MODEL "$TARGET_DEV" | tr -s ' ' | xargs)"
note "target:        $TARGET_DEV"
note "target model:  $TARGET_MODEL"

if [[ "$TARGET_MODEL" != *"$EXPECTED_MODEL_MATCH"* ]]; then
  die "target model does not contain '$EXPECTED_MODEL_MATCH' — refusing to continue"
fi
if [[ "$TARGET_MODEL" == *"$FORBIDDEN_MODEL_MATCH"* ]]; then
  die "target model matches Windows disk '$FORBIDDEN_MODEL_MATCH' — refusing"
fi

# Same test, at the partition level: nvme0n1p2 should be our ext4 root
# mounted at /. If it isn't, something has changed since inventory.
ROOT_SRC="$(findmnt -no SOURCE /)"
if [[ "$ROOT_SRC" != "${TARGET_DEV}p2" && "$ROOT_SRC" != "${TARGET_DEV}"* ]]; then
  echo "warning: / is mounted from $ROOT_SRC, not a partition of $TARGET_DEV" >&2
  [[ $ASSUME_YES -eq 1 ]] || { read -r -p "continue anyway? [y/N] " a; [[ "$a" =~ ^[yY]$ ]] || exit 1; }
fi

# --- size / space estimate ----------------------------------------------

SRC_BYTES="$(blockdev --getsize64 "$TARGET_DEV")"
SRC_H="$(numfmt --to=iec --suffix=B "$SRC_BYTES")"

# Budget: assume ~10% of the raw size for the compressed output (well-trimmed
# SSD with 67 GB of actual content compresses very well with zstd). Require
# at least 2x that as headroom.
BUDGET=$(( SRC_BYTES / 10 * 2 ))
BUDGET_H="$(numfmt --to=iec --suffix=B "$BUDGET")"

AVAIL_BYTES="$(df -B1 --output=avail "$OUT_ROOT" | tail -1 | tr -d ' ')"
AVAIL_H="$(numfmt --to=iec --suffix=B "$AVAIL_BYTES")"

note "source size:   $SRC_H ($SRC_BYTES bytes)"
note "space budget:  ~$BUDGET_H (compressed estimate + headroom)"
note "available:     $AVAIL_H"

(( AVAIL_BYTES >= BUDGET )) || die "insufficient space at $OUT_ROOT"

# --- confirm -------------------------------------------------------------

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUT_ROOT/ubuntu-dd-$TS"
IMG="$OUT/nvme0n1.img.zst"

cat <<EOF

about to:
  read  $TARGET_DEV ($SRC_H, model: $TARGET_MODEL)
  write $IMG
  compress with zstd -$ZSTD_LEVEL (threads=$ZSTD_THREADS, long=27)

note: filesystem is live. Stop non-essential services and pause heavy I/O
during the image if you care about a quiescent snapshot. ext4 journal +
fsck on restore will clean up minor inconsistencies if you don't.

EOF

if (( ! ASSUME_YES )); then
  read -r -p "proceed? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { note "aborted"; exit 1; }
fi

mkdir -p "$OUT" || die "could not create $OUT"

# --- dd -> zstd ----------------------------------------------------------

step "imaging"
sync; sync  # best-effort flush before we start reading the block device

START_EPOCH="$(date +%s)"

# dd emits human progress to stderr via status=progress; zstd prints its
# own summary on completion. Pipe failure causes the whole chain to fail
# thanks to pipefail.
dd if="$TARGET_DEV" bs=4M status=progress conv=noerror,sync \
  | zstd -T"$ZSTD_THREADS" -"$ZSTD_LEVEL" --long=27 -o "$IMG"

END_EPOCH="$(date +%s)"
ELAPSED=$(( END_EPOCH - START_EPOCH ))

# --- verify --------------------------------------------------------------

step "verify"
note "zstd -t (archive integrity)"
zstd -t "$IMG" || die "zstd -t failed — archive is corrupt"

note "sha256sum (this reads the whole archive — takes a minute)"
SHA="$(sha256sum "$IMG" | awk '{print $1}')"

IMG_BYTES="$(stat -c %s "$IMG")"
IMG_H="$(numfmt --to=iec --suffix=B "$IMG_BYTES")"
RATIO="$(awk -v s="$SRC_BYTES" -v d="$IMG_BYTES" 'BEGIN { printf "%.2fx\n", s/d }')"

# --- manifest + restore notes -------------------------------------------

cat > "$OUT/manifest.txt" <<EOF
nori Ubuntu full-disk image
---------------------------
script version:   $SCRIPT_VERSION
timestamp (UTC):  $TS
host:             $HOST
source device:    $TARGET_DEV
source model:     $TARGET_MODEL
source size:      $SRC_BYTES bytes ($SRC_H)
image path:       $IMG
image size:       $IMG_BYTES bytes ($IMG_H)
compression:      zstd -$ZSTD_LEVEL --long=27, threads=$ZSTD_THREADS
ratio:            $RATIO
elapsed:          ${ELAPSED}s
sha256:           $SHA
EOF

cat > "$OUT/RESTORE.md" <<EOF
# Restoring $IMG

This is a block-level image of $TARGET_DEV as of $TS UTC.

## Prerequisites

- A live USB that includes \`zstd\`, \`dd\`, and \`sha256sum\` (Ubuntu Live,
  SystemRescue, NixOS installer, Gparted Live — any modern distro).
- Physical access to the machine (or IPMI / remote console).
- One Touch connected and mounted read-only.

## Verify before restoring

    sha256sum $IMG
    # expect: $SHA

    zstd -t $IMG
    # expect: "$IMG : ... OK"

## Restore (DESTRUCTIVE — wipes $TARGET_DEV)

First, **confirm the target disk** by model:

    lsblk -dn -o NAME,SIZE,MODEL
    # look for "$EXPECTED_MODEL_MATCH" — the Ubuntu disk.
    # DO NOT write to any disk whose model contains "$FORBIDDEN_MODEL_MATCH"
    # (that is the Windows disk; the image will overwrite it silently).

Then restore:

    zstd -d -c $IMG | dd of=$TARGET_DEV bs=4M status=progress oflag=direct
    sync

Reboot. ext4 will journal-replay on first mount; fsck may run once.

## Scope

The image is $TARGET_DEV only. The Windows disk (nvme1n1), IronWolf Pro
(sda), and One Touch (sdb) are not touched by this snapshot.
EOF

# --- summary -------------------------------------------------------------

step "done"
note "image:     $IMG"
note "size:      $IMG_H (ratio: $RATIO)"
note "sha256:    $SHA"
note "elapsed:   ${ELAPSED}s"
note "restore:   $OUT/RESTORE.md"
