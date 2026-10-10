#!/usr/bin/env bash
# nori-subvolume-migrate — convert classified re-derivable paths into
# nested Btrfs subvolumes. Classification is owned by nori.fs; the same
# registry derives the boundaries, snapshot filter, and Restic exclusions.
#
# Home-cache initialization remains guarded but automatic at boot; the
# /srv/share/projects unit is manual so its live writers can be quiesced.
# It validates device/filesystem identity, refuses busy paths, copies with
# reflinks, verifies the copy, and keeps a read-only nested rollback snapshot.
# The verified plain-directory duplicate is removed only after atomic exchange,
# full tree comparisons, and a second writer check. Any uncertain state keeps
# every available copy and exits loudly. Parent-restic exclusion derivation
# also covers the sibling staging and rollback locations used during cutover.
set -euo pipefail

die() { printf 'nori-subvolume-migrate: %s\n' "$*" >&2; exit 1; }
note() { printf 'nori-subvolume-migrate: %s\n' "$*"; }
usage() {
  printf 'usage: %s --device DISK --mount-device PARTITION --fs-label LABEL --parent PATH... -- PATH...\n' "$0" >&2
  exit 2
}

device=""
mount_device=""
fs_label=""
parents=()
paths=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --device) [ "$#" -ge 2 ] || usage; device="$2"; shift 2 ;;
    --mount-device) [ "$#" -ge 2 ] || usage; mount_device="$2"; shift 2 ;;
    --fs-label) [ "$#" -ge 2 ] || usage; fs_label="$2"; shift 2 ;;
    --parent) [ "$#" -ge 2 ] || usage; parents+=("${2%/}"); shift 2 ;;
    -h|--help) usage ;;
    --) shift; paths+=("$@"); break ;;
    -*) die "unknown flag: $1" ;;
    *) paths+=("$1"); shift ;;
  esac
done
[ -n "$device" ] && [ -n "$mount_device" ] && [ -n "$fs_label" ] || usage
[ "${#parents[@]}" -gt 0 ] && [ "${#paths[@]}" -gt 0 ] || usage
for parent in "${parents[@]}"; do
  [ -n "$parent" ] || die "--parent must not be filesystem root"
done

# Resolve the declared disk and mounted filesystem before any skip or change.
[ -e "$device" ] || die "declared root disk device does not exist: $device"
expect_disk="$(readlink -f -- "$device")"
[ -b "$expect_disk" ] || die "declared root disk device is not a block device: $device"
[ -e "$mount_device" ] || die "declared Btrfs partition does not exist: $mount_device"
expect_part="$(readlink -f -- "$mount_device")"
[ -b "$expect_part" ] || die "declared Btrfs partition is not a block device: $mount_device"
pkname="$(lsblk -no pkname -- "$expect_part")" || die "cannot read the parent disk of $mount_device"
if [ -n "$pkname" ]; then
  parent_disk="$(readlink -f -- "/dev/$pkname")" || die "cannot resolve parent disk for $mount_device"
else
  parent_disk="$expect_part"
fi
[ "$parent_disk" = "$expect_disk" ] || die "$mount_device is on $parent_disk, not on declared root disk $device"

writer_block_reason() {
  local dir="$1" out rc
  set +e
  out="$(lsof -t +D "$dir" 2>&1)"
  rc=$?
  set -e
  case "$rc" in
    1) if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi; return 1 ;;
    0) if [ -n "$out" ]; then printf '%s' "$out"; else printf 'lsof exited 0 without listing a file for %s' "$dir"; fi; return 0 ;;
    *) printf 'lsof exited %s: %s' "$rc" "$out"; return 0 ;;
  esac
}

owner_reference() {
  if [ -d "$parent_dir" ]; then printf '%s' "$parent_dir"; else printf '%s' "$owner_parent"; fi
}
adopt_ownership() {
  local reference
  reference="$(owner_reference)"
  [ -d "$reference" ] || die "cannot derive owner for $path: $reference does not exist"
  chown --reference="$reference" -- "$1"
  chmod --reference="$reference" -- "$1"
}

migrated=0
created=0
for raw_path in "${paths[@]}"; do
  path="${raw_path%/}"
  [ -n "$path" ] && [ "$path" = "$raw_path" ] || die "path must be non-empty and must not end with a slash: $raw_path"
  owner_parent=""
  for candidate in "${parents[@]}"; do
    case "$path" in "$candidate"/*) owner_parent="$candidate"; break ;; esac
  done
  [ -n "$owner_parent" ] || die "$path is not below any declared backed-up parent"
  parent_dir="$(dirname -- "$path")"
  base_name="$(basename -- "$path")"
  staging="${parent_dir}/.${base_name}.nori-subvolume-migration-staging"
  rollback="${parent_dir}/.${base_name}.nori-subvolume-migration-rollback"
  probe="$path"
  [ -e "$probe" ] || probe="$parent_dir"
  mount_target="$(findmnt -kno TARGET --target "$probe")" || die "cannot resolve mount for $probe"
  [ ! -L "$path" ] || die "$path is a symlink; refusing to replace it"
  if [ -e "$path" ] && [ ! -d "$path" ]; then die "$path exists and is not a directory"; fi
  fstype="$(findmnt -kno FSTYPE --target "$probe")" || die "cannot read filesystem type for $probe"
  [ "$fstype" = btrfs ] || die "$probe is on $fstype, not Btrfs"
  source="$(findmnt -kno SOURCE --target "$probe")" || die "cannot read source for $probe"
  source_dev="${source%%[*}"
  [ "$(readlink -f -- "$source_dev")" = "$expect_part" ] || die "$probe is mounted from $source_dev, not declared partition $mount_device"
  shown="$(btrfs filesystem show -- "$mount_target")" || die "cannot read Btrfs identity for $probe"
  uuid="$(printf '%s\n' "$shown" | sed -n 's/.*uuid: \([0-9a-fA-F-][0-9a-fA-F-]*\).*/\1/p')"
  label="$(printf '%s\n' "$shown" | sed -n "s/^Label: '\([^']*\)'.*/\1/p")"
  [ -n "$uuid" ] || die "could not read Btrfs FsUUID backing $probe"
  dev_uuid="$(blkid -o value -s UUID -- "$expect_part")" || die "cannot read filesystem UUID of $mount_device"
  [ "$uuid" = "$dev_uuid" ] || die "FsUUID mismatch for $probe: $uuid != $dev_uuid"
  [ "$label" = "$fs_label" ] || die "Btrfs label mismatch for $probe: '$label' (expected '$fs_label')"

  if [ -e "$path" ] && btrfs subvolume show -- "$path" >/dev/null 2>&1; then
    if [ "$(stat -c '%u:%g' -- "$path")" = 0:0 ]; then
      adopt_ownership "$path"
      note "$path was a root-owned subvolume; adopted owner from $(owner_reference)"
    else
      note "$path is already a subvolume — nothing to migrate"
    fi
    continue
  fi
  if [ -e "$path" ] && [ "$mount_target" = "$path" ]; then die "$path is a mount point; refusing to migrate it"; fi
  if [ ! -e "$path" ]; then
    [ -d "$parent_dir" ] || die "cannot create $path: parent $parent_dir does not exist"
    btrfs subvolume create -- "$path" >/dev/null || die "cannot create boundary $path"
    adopt_ownership "$path"
    note "created empty subvolume boundary $path owned like $(owner_reference)"
    created=$((created + 1))
    continue
  fi
  [ ! -e "$staging" ] || die "stale staging path exists: $staging — inspect and resolve it deliberately"
  [ ! -e "$rollback" ] || die "rollback subvolume already exists: $rollback — inspect it deliberately before retrying"
  writer_reason=""
  if writer_reason="$(writer_block_reason "$path")"; then die "refusing to migrate busy path $path: $writer_reason"; fi

  btrfs subvolume create -- "$staging" >/dev/null || die "cannot create staging subvolume $staging"
  if ! cp -a --reflink=auto -- "$path/." "$staging/"; then
    btrfs subvolume delete -- "$staging" >/dev/null 2>&1 || note "WARNING: staging remains at $staging"
    die "copy failed for $path — original is untouched"
  fi
  if ! diff -r --no-dereference -- "$path" "$staging" >/dev/null; then
    btrfs subvolume delete -- "$staging" >/dev/null 2>&1 || note "WARNING: staging remains at $staging"
    die "verification failed for $path — original is untouched"
  fi
  chmod --reference="$path" -- "$staging"
  chown --reference="$path" -- "$staging"
  touch --reference="$path" -- "$staging"
  if writer_reason="$(writer_block_reason "$path")"; then
    btrfs subvolume delete -- "$staging" >/dev/null 2>&1 || note "WARNING: staging remains at $staging"
    die "refusing to swap busy path $path: $writer_reason — original is untouched"
  fi

  btrfs subvolume snapshot -r "$staging" "$rollback" >/dev/null || {
    btrfs subvolume delete -- "$staging" >/dev/null 2>&1 || note "WARNING: staging remains at $staging"
    die "cannot create rollback snapshot $rollback — original is untouched"
  }
  if ! diff -r --no-dereference -- "$path" "$rollback" >/dev/null; then
    btrfs subvolume delete -- "$rollback" >/dev/null 2>&1 || note "WARNING: rollback snapshot remains at $rollback"
    btrfs subvolume delete -- "$staging" >/dev/null 2>&1 || note "WARNING: staging remains at $staging"
    die "rollback verification failed for $path — original is untouched"
  fi
  if ! mv --exchange --no-copy --no-target-directory -- "$path" "$staging"; then
    die "cannot atomically exchange verified staging into $path — original and staging are preserved"
  fi
  # At this point path is the verified live subvolume; staging is the old
  # plain directory. Compare all three before removing only that duplicate.
  if ! diff -r --no-dereference -- "$staging" "$path" >/dev/null || ! diff -r --no-dereference -- "$staging" "$rollback" >/dev/null; then
    die "post-exchange verification failed for $path; original remains at $staging, rollback at $rollback; parent snapshots still include the plain original until resolved"
  fi
  if writer_reason="$(writer_block_reason "$staging")"; then
    die "late writer holds original $staging: $writer_reason; original and rollback are preserved; parent snapshots still include the plain original until resolved"
  fi
  if writer_reason="$(writer_block_reason "$path")"; then
    die "late writer holds live subvolume $path: $writer_reason; original and rollback are preserved; parent snapshots still include the plain original until resolved"
  fi
  if ! diff -r --no-dereference -- "$staging" "$path" >/dev/null || ! diff -r --no-dereference -- "$staging" "$rollback" >/dev/null; then
    die "tree changed during final writer check for $path; original remains at $staging and parent snapshots still include it"
  fi
  if ! rm -rf --one-file-system -- "$staging"; then
    die "verified duplicate could not be removed from $staging; rollback remains at $rollback; parent snapshots still include the plain original until resolved"
  fi
  migrated=$((migrated + 1))
  note "$path is now a nested subvolume; read-only rollback is preserved at $rollback; verified plain duplicate removed"
done
note "migration complete: $migrated path(s) converted, $created boundary(ies) created"
