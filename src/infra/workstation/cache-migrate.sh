#!/usr/bin/env bash
#
# nori-cache-migrate — put explicitly disposable cache directories on
# nested @home btrfs subvolumes.
#
# The classification lives in the nori.fs registry (disko.nix): entries
# with tier "re-derivable" under the home path are the only disposable
# caches. This script is the runtime half:
#
#   * an existing cache directory is copied into a staging subvolume,
#     verified, and swapped into place with a single atomic
#     renameat2(RENAME_EXCHANGE) — the path is never absent, so a tool
#     starting at that moment cannot have a plain directory created
#     underneath the boundary (nor can the staging tree end up nested
#     inside the cache path);
#   * the pre-migration directory (the exchange's other half) is then
#     renamed next to the boundary as rollback material; if that rename
#     fails the original is left in place and reported, never discarded;
#   * an absent cache directory gets the boundary created up front, owned
#     like the cache's parent directory, so the boundary persists instead
#     of appearing only after a later reboot;
#   * a root-owned boundary left by an install-time disko run adopts that
#     same ownership (the boundary directory only — never its contents);
#   * nothing is ever formatted, mounted over data, or delegated to
#     disko, and the original cache contents are never deleted.
#
# Invariants — each violation exits nonzero without making changes, and
# nothing here is silenced:
#   * the mounted filesystem really is the declared root Btrfs: the home
#     partition resolves to the declared disk by-id, is btrfs, and reports
#     the expected FsUUID and label;
#   * no process holds the cache path open (checked before the copy and
#     again immediately before the swap);
#   * a path that is already a subvolume is left alone apart from the
#     install-time ownership case above;
#   * a path that is a symlink or a mount point is refused; a path whose
#     parent or owning home directory does not exist is refused rather
#     than created with a guessed owner.
#
# Usage:
#   nori-cache-migrate --device DISK --mount-device PARTITION \
#     --fs-label LABEL --home HOMEPATH PATH...
#
set -euo pipefail

die() { printf 'nori-cache-migrate: %s\n' "$*" >&2; exit 1; }
note() { printf 'nori-cache-migrate: %s\n' "$*"; }

usage() {
  printf 'usage: %s --device DISK --mount-device PARTITION --fs-label LABEL --home HOMEPATH PATH...\n' "$0" >&2
  exit 2
}

device=""
mount_device=""
fs_label=""
home_path=""
paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      [ "$#" -ge 2 ] || usage
      device="$2"
      shift 2
      ;;
    --mount-device)
      [ "$#" -ge 2 ] || usage
      mount_device="$2"
      shift 2
      ;;
    --fs-label)
      [ "$#" -ge 2 ] || usage
      fs_label="$2"
      shift 2
      ;;
    --home)
      [ "$#" -ge 2 ] || usage
      home_path="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    --)
      shift
      paths+=("$@")
      break
      ;;
    -*) die "unknown flag: $1" ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

[ -n "$device" ] || usage
[ -n "$mount_device" ] || usage
[ -n "$fs_label" ] || usage
[ -n "$home_path" ] || usage
[ "${#paths[@]}" -gt 0 ] || usage
home_path="${home_path%/}"
[ -n "$home_path" ] || die "--home must not be the filesystem root"

# ── Root Btrfs identity ────────────────────────────────────────────────
# disk by-id -> parent disk of the home partition; the partition must
# resolve onto that disk, and the filesystem it carries must report the
# label the disko layout declares. A replaced or mis-bound drive fails
# here instead of touching the wrong filesystem.
[ -e "$device" ] || die "declared root disk device does not exist: $device"
expect_disk="$(readlink -f -- "$device")"
[ -b "$expect_disk" ] || die "declared root disk device is not a block device: $device"
[ -e "$mount_device" ] || die "declared home partition device does not exist: $mount_device"
expect_part="$(readlink -f -- "$mount_device")"
[ -b "$expect_part" ] || die "declared home partition is not a block device: $mount_device"

pkname="$(lsblk -no pkname -- "$expect_part")" || die "cannot read the parent disk of $mount_device"
if [ -n "$pkname" ]; then
  parent_disk="$(readlink -f -- "/dev/$pkname")"
else
  # Filesystem directly on the declared device (no partition table):
  # the mount device IS the disk.
  parent_disk="$expect_part"
fi
[ "$parent_disk" = "$expect_disk" ] ||
  die "$mount_device is on ${parent_disk}, not on the declared root disk $device"

# Writer guard. Prints a blocking reason and returns 0 when the cache
# path must not be migrated; prints nothing and returns 1 when the scan
# completed and found no writer.
#
# lsof noise is deliberately NOT suppressed: lsof exits 1 both when it
# finds nothing and when it fails, so its exit status alone is not a
# usable signal. Only "exit 1 and no output" counts as idle — any output
# (a pid, a warning, a diagnostic) is reported as a blocker rather than
# assumed healthy, and the message carries the output so a human can tell
# a busy cache from an unrelated scan warning.
writer_block_reason() {
  local dir="$1" out rc
  set +e
  out="$(lsof -t +D "$dir" 2>&1)"
  rc=$?
  set -e
  case "$rc" in
    1)
      if [ -n "$out" ]; then
        printf '%s' "$out"
        return 0
      fi
      return 1
      ;;
    0)
      if [ -n "$out" ]; then
        printf '%s' "$out"
      else
        printf 'lsof exited 0 without listing a file for %s' "$dir"
      fi
      return 0
      ;;
    *)
      printf 'lsof exited %s: %s' "$rc" "$out"
      return 0
      ;;
  esac
}

discard_staging() {
  # Removes the staging subvolume holding OUR copy, used only on paths
  # where the exchange has not happened yet (so the original is still the
  # cache directory). Never called after a successful exchange, where the
  # staging path holds the original.
  if ! btrfs subvolume delete -- "$staging" >/dev/null 2>&1; then
    note "WARNING: could not remove staging subvolume $staging — remove it manually"
  fi
}

# Ownership reference for a boundary that has to be created or adopted:
# the cache's parent directory when it exists (the directory the tool
# writes into), else the owning home directory. Both are derived from the
# path itself — no uid is ever hardcoded.
ownership_reference() {
  if [ -d "$parent_dir" ]; then
    printf '%s' "$parent_dir"
  else
    printf '%s' "$user_home"
  fi
}

adopt_ownership() {
  local reference
  reference="$(ownership_reference)"
  [ -d "$reference" ] || die "cannot derive an owner for $path: $reference does not exist"
  chown --reference="$reference" -- "$1"
  chmod --reference="$reference" -- "$1"
}

migrated=0
created=0
for raw_path in "${paths[@]}"; do
  path="${raw_path%/}"
  [ -n "$path" ] || die "empty path argument"
  [ "$path" = "$raw_path" ] || die "path must not end with a slash: $raw_path"
  case "$path" in
    "$home_path"/*) : ;;
    *) die "$path is not below the configured home path $home_path" ;;
  esac

  relative="${path#"$home_path/"}"
  user_home="$home_path/${relative%%/*}"
  parent_dir="$(dirname -- "$path")"
  base_name="$(basename -- "$path")"

  # Resolve the mount the cache lives on. For an absent directory the
  # deepest existing directory (its parent) is the probe: a path that does
  # not exist yet cannot be resolved by findmnt.
  if [ -e "$path" ]; then
    probe="$path"
  else
    probe="$parent_dir"
  fi
  mount_target="$(findmnt -kno TARGET --target "$probe")" || die "cannot resolve the mount for $probe"

  # Type guards before anything else: `btrfs subvolume show` follows
  # symlinks, and a broken symlink looks absent to `-e`.
  [ ! -L "$path" ] || die "$path is a symlink; refusing to replace it"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    die "$path exists and is not a directory"
  fi

  # Identity validation happens before ANY branch below can skip, adopt
  # ownership, create or mutate: a boundary that lives on another
  # filesystem or another disk is refused, never adopted.
  fstype="$(findmnt -kno FSTYPE --target "$probe")" || die "cannot read the filesystem type for $probe"
  [ "$fstype" = "btrfs" ] || die "$probe is on $fstype, not btrfs"

  source="$(findmnt -kno SOURCE --target "$probe")" || die "cannot read the mount source for $probe"
  source_dev="${source%%[*}"
  [ "$(readlink -f -- "$source_dev")" = "$expect_part" ] ||
    die "$probe is mounted from $source_dev, not from the declared home partition $mount_device"

  # `btrfs filesystem show` identifies a filesystem by its mount point (a
  # nested path is rejected), so probe the mount resolved above.
  shown="$(btrfs filesystem show -- "$mount_target")" || die "cannot read btrfs filesystem info for $probe"
  uuid="$(printf '%s\n' "$shown" | sed -n "s/.*uuid: \([0-9a-fA-F-]\{1,\}\).*/\1/p")"
  label="$(printf '%s\n' "$shown" | sed -n "s/^Label: '\([^']*\)'.*/\1/p")"
  [ -n "$uuid" ] || die "could not read the btrfs FsUUID backing $probe"
  dev_uuid="$(blkid -o value -s UUID -- "$expect_part")" || die "cannot read the filesystem UUID of $mount_device"
  [ "$uuid" = "$dev_uuid" ] ||
    die "FsUUID mismatch for $probe: the filesystem reports $uuid, $mount_device reports $dev_uuid"
  [ "$label" = "$fs_label" ] ||
    die "btrfs label mismatch for $probe: '$label' (expected '$fs_label')"

  if [ -e "$path" ] && btrfs subvolume show -- "$path" >/dev/null 2>&1; then
    # Steady state after a run — or, on a freshly installed machine, the
    # empty boundary disko created as root. Adopt the derived owner for
    # that case only; contents are never touched and an existing owner is
    # left alone.
    if [ "$(stat -c '%u:%g' -- "$path")" = "0:0" ]; then
      adopt_ownership "$path"
      note "$path was a root-owned subvolume; adopted ownership from $(ownership_reference)"
    else
      note "$path is already a subvolume — nothing to migrate"
    fi
    continue
  fi

  # A mount point that is not a btrfs subvolume root (a bind mount) must
  # never be swapped: its contents belong to another mount.
  if [ -e "$path" ] && [ "$mount_target" = "$path" ]; then
    die "$path is itself a mount point; refusing to migrate a mounted path"
  fi

  if [ ! -e "$path" ]; then
    # Create the boundary before any tool can write a plain directory
    # there, so the separation persists without waiting for a reboot. The
    # owner comes from the cache parent (or the home directory); if that
    # reference is missing, refuse rather than guess.
    [ -d "$parent_dir" ] || die "cannot create $path: parent $parent_dir does not exist"
    btrfs subvolume create -- "$path" >/dev/null || die "cannot create cache boundary $path"
    adopt_ownership "$path"
    note "created empty cache boundary $path owned like $(ownership_reference)"
    created=$((created + 1))
    continue
  fi

  backup="${path}.pre-cache-separation"
  staging="${parent_dir}/.${base_name}.cache-migration-staging"

  [ ! -e "$backup" ] ||
    die "rollback material already exists: $backup — inspect and remove it deliberately before re-running"
  [ ! -e "$staging" ] || die "stale staging path exists: $staging — remove it deliberately"

  writer_reason=""
  if writer_reason="$(writer_block_reason "$path")"; then
    die "refusing to migrate a busy cache $path: $writer_reason"
  fi

  btrfs subvolume create -- "$staging" >/dev/null || die "cannot create staging subvolume $staging"

  if ! cp -a --reflink=auto -- "$path/." "$staging/"; then
    discard_staging
    die "copy failed for $path — the original is untouched"
  fi
  if ! diff -r --no-dereference -- "$path" "$staging" >/dev/null; then
    discard_staging
    die "verification failed: the copied tree differs from $path — the original is untouched"
  fi
  # The staging subvolume replaces the original directory itself, so it
  # must carry the original directory's own mode/owner/timestamp (the
  # contents were already copied with cp -a).
  chmod --reference="$path" -- "$staging"
  chown --reference="$path" -- "$staging"
  touch --reference="$path" -- "$staging"

  # Second check, immediately before the swap: the copy is complete, so a
  # writer that appeared mid-copy must not end up split across the
  # rollback directory and the new boundary. This blocked case discards
  # only our copy; the original is still the cache directory.
  if writer_reason="$(writer_block_reason "$path")"; then
    discard_staging
    die "refusing to swap a busy cache $path: $writer_reason — the original is untouched"
  fi

  # Atomic cutover: swap the verified copy and the original directory in
  # one renameat2(RENAME_EXCHANGE). The cache path always refers to a
  # directory, so a tool starting at this moment cannot slip a plain
  # directory under the boundary, and the staging tree can never end up
  # nested inside the cache path.
  if ! mv --exchange --no-copy --no-target-directory -- "$path" "$staging"; then
    die "cannot swap the verified copy into $path — the original is still there and the copy is preserved at $staging; nothing was discarded"
  fi

  # The other half of the exchange is the original directory.
  # `--no-target-directory` + `--update=none-fail` make an existing
  # rollback name a loud failure instead of moving the original INSIDE it.
  if ! mv --update=none-fail --no-target-directory -- "$staging" "$backup"; then
    die "$path is now the migrated subvolume, but the original directory could not be moved to $backup — it is preserved at $staging; move it deliberately, do not delete it"
  fi

  migrated=$((migrated + 1))
  note "$path is now a nested subvolume; the pre-migration directory is preserved at $backup"
done

note "migration complete: $migrated path(s) converted, $created boundary(ies) created"
