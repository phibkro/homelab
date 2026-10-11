#!/usr/bin/env bash
#
# Focused semantic test for generic nested-subvolume migration
# (src/infra/workstation/subvolume-migrate.sh). Everything runs against
# real disposable loop-backed Btrfs filesystems under a temp directory —
# never the live root, /home or /srv/share, or production data.
#
# Coverage:
#   1. a busy cache refuses migration — an open file descriptor and a
#      process whose cwd is inside the cache both block it, and the
#      original stays untouched with no leftovers;
#   2. a wrong device or a wrong btrfs label refuses migration and
#      changes nothing (a mismatch is never silenced);
#   3. structural refusals, all of them AFTER full identity validation:
#      a symlink, a symlink pointing AT a subvolume (`btrfs subvolume show`
#      follows symlinks), a foreign filesystem mounted at the path, a bind
#      mount on the declared filesystem, leftover rollback material and a
#      stale staging directory;
#   3b. a root-owned boundary on a DIFFERENT filesystem than declared is
#      refused and left completely alone — identity validation runs before
#      any skip/adopt/create branch;
#   4. an lsof scan that does not complete cleanly is a blocker, never a
#      healthy result — a nonstandard exit status with no output, and a
#      success status that lists nothing, both refuse;
#   5. the writer re-check before the cutover discards ONLY the copied
#      staging subvolume and leaves the original cache directory intact;
#   6. an absent cache directory gets its boundary created up front with
#      ownership derived from the cache parent;
#   7. a root-owned boundary (an install-time disko creation) adopts that
#      derived ownership — the boundary directory only, never its contents;
#   8. migration preserves contents and metadata, with a read-only nested
#      rollback snapshot; only the verified duplicate original is removed;
#   9. the cutover is one atomic renameat2(RENAME_EXCHANGE);
#  10. a second run is a no-op;
#  11. both snapshots and Restic omit game paths but retain Steam state;
#  12. manual Steam migration refuses either active pinned process and
#      the secondary library can create missing nested parents safely.
#
# Usage: subvolume-migration_test.sh <path-to-subvolume-migrate.sh>
# Requires: sudo -n, btrfs-progs, GNU coreutils >= 9.1, strace, lsof,
# restic, findutils, util-linux, diffutils, gnused, nix, jq.

set -euo pipefail

script="${1:?usage: subvolume-migration_test.sh <path-to-subvolume-migrate.sh>}"
script="$(readlink -f -- "$script")"
repo="$(readlink -f -- "$(dirname -- "$script")/../../..")"
suffixes="$(nix eval --json --file "$repo/src/infra/common/nixos/storage/subvolume-paths.nix" --apply 'p: { inherit (p) stagingSuffix rollbackSuffix; }')"
staging_suffix="$(jq -r .stagingSuffix <<<"$suffixes")"
rollback_suffix="$(jq -r .rollbackSuffix <<<"$suffixes")"
migration_args=(--staging-suffix "$staging_suffix" --rollback-suffix "$rollback_suffix")

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

as_root() {
  if [ "$1" = "$script" ]; then
    shift
    sudo -n env "PATH=$PATH" "$script" "${migration_args[@]}" "$@"
  else
    sudo -n env "PATH=$PATH" "$@"
  fi
}

work="$(mktemp -d /tmp/nori-subvolume-migration-test.XXXXXX)"
img="$work/cache.img"
img_other="$work/other.img"
root="$work/fs"
other_root="$work/other"
loop=""
loop_other=""
holders=()
process_stub_dir="$work/process-stubs"
active_process_dir="$work/active-processes"
mkdir -p "$process_stub_dir" "$active_process_dir"
cat >"$process_stub_dir/pgrep" <<PGREP_STUB
#!/usr/bin/env bash
process="\$2"
if [ -e "$active_process_dir/\$process" ]; then
  printf '123\n'
  exit 0
fi
exit 1
PGREP_STUB
chmod +x "$process_stub_dir/pgrep"
PATH="$process_stub_dir:$PATH"
export PATH

cleanup() {
  set +e
  for pid in "${holders[@]:-}"; do
    kill "$pid" 2>/dev/null
  done
  wait 2>/dev/null
  # Nested test mounts (e.g. the tmpfs refusal case) first, so the loop
  # filesystem can actually be unmounted; root-owned subvolumes in the
  # scratch tree need root to remove.
  as_root umount -R "$root" 2>/dev/null
  as_root umount -R "$other_root" 2>/dev/null
  if [ -n "$loop" ]; then as_root losetup -d "$loop" 2>/dev/null; fi
  if [ -n "$loop_other" ]; then as_root losetup -d "$loop_other" 2>/dev/null; fi
  as_root rm -rf "$work" 2>/dev/null
  rm -rf "$work" 2>/dev/null
}
trap cleanup EXIT

# ── disposable filesystems ────────────────────────────────────────────
truncate -s 512M "$img"
truncate -s 128M "$img_other"
as_root mkfs.btrfs -q -L cache-test "$img"
as_root mkfs.btrfs -q -L other-test "$img_other"
loop="$(as_root losetup --find --show "$img")"
loop_other="$(as_root losetup --find --show "$img_other")"
mkdir -p "$root" "$other_root"
as_root mount "$loop" "$root"
as_root mount "$loop_other" "$other_root"

# Instantiate the actual declared install layout, not a copied subvolume map.
layout="$(nix eval --offline --json "$repo#nixosConfigurations.workstation.config" --apply 'c: { subvolumes = builtins.attrNames c.disko.devices.disk.main.content.partitions.root.content.subvolumes; share = builtins.head (builtins.filter (v: builtins.match "subvol=.*" v != null) c.fileSystems."/srv/share".options); excludes = c.nori.backups.user-data.exclude; }')"
install_root="$root/install-layout"
as_root mkdir "$install_root"
while IFS= read -r name; do
  as_root mkdir -p "$(dirname -- "$install_root/$name")"
  as_root btrfs subvolume create "$install_root/$name" >/dev/null
done < <(jq -r ' .subvolumes[] ' <<<"$layout")
share_source="$(jq -r .share <<<"$layout")"
installed_share="$install_root/${share_source#subvol=}"
as_root btrfs subvolume show "$installed_share/projects" >/dev/null ||
  fail "declared projects boundary is not nested inside the mounted share subvolume"
as_root sh -c "printf 'not-in-snapshot\n' > \"\$1/projects/artifact\"; printf 'keep\n' > \"\$1/protected.txt\"" sh "$installed_share"
as_root btrfs subvolume snapshot -r "$installed_share" "$root/installed-share-snapshot" >/dev/null
[ ! -e "$root/installed-share-snapshot/projects/artifact" ] || fail "fresh install snapshot includes projects"
[ "$(cat "$root/installed-share-snapshot/protected.txt")" = keep ] || fail "fresh install snapshot lost neighboring files"
pass "declared fresh-install layout excludes projects from the actual share snapshot"

h="$root/home/nori"
cache_pip="$h/.cache/pip"
cache_uv="$h/.cache/uv"
cache_nix="$h/.cache/nix"
cache_keep="$h/.cache/keepme"
cache_browser="$h/.cache/chromium/Default/Cache"
omp="$h/.omp/agent/cache"
share="$root/share"
projects="$share/projects"

# Both parent paths are backed-up source subvolumes. Nested targets must
# disappear from parent snapshots without any mount hiding the live paths.
as_root btrfs subvolume create "$root/home" >/dev/null
as_root btrfs subvolume create "$share" >/dev/null
as_root chown 1000:100 "$root/home" "$share"
mkdir -p "$cache_pip/subdir" "$cache_uv" "$cache_nix" "$cache_keep" "$cache_browser" "$omp"
mkdir -p "$projects/app" "$projects/local-only"
printf 'alpha\n' > "$cache_pip/a.txt"
printf 'beta\n' > "$cache_pip/subdir/b.txt"
head -c 262144 /dev/urandom > "$cache_pip/blob.bin"
ln -s a.txt "$cache_pip/link"
printf 'uv\n' > "$cache_uv/u.txt"
printf 'nix\n' > "$cache_nix/n.txt"
printf 'keep\n' > "$cache_keep/protected.txt"
printf 'browser-state\n' > "$cache_browser/entry"
printf 'omp-agent-cache\n' > "$omp/omp.txt"
printf 'tracked-style content\n' > "$projects/app/README"
printf 'local ignored/uncommitted data\n' > "$projects/local-only/notes"
printf 'project-neighbour\n' > "$share/projects-neighbour.txt"
chmod 0751 "$cache_pip/subdir"
chmod 0640 "$cache_pip/a.txt"
chmod 0700 "$cache_pip"
chown -R 1000:100 "$h" "$projects"
touch -d '2020-01-02 03:04:05' "$cache_pip" "$cache_pip/a.txt" "$cache_pip/subdir"
manifest() { find "$1" -mindepth 1 -printf '%P|%y|%m|%U|%G|%s|%l|%T@\n' | sort; }
digest() { find "$1" -type f -print0 | sort -z | xargs -0 -r sha256sum | sha256sum; }
meta() { stat -c '%a %u %g %Y %i' "$1"; }

pre_pip_manifest="$(manifest "$cache_pip")"
pre_pip_digest="$(digest "$cache_pip")"
pre_pip_meta="$(stat -c '%a %u %g %Y' "$cache_pip")"
pre_pip_inode="$(stat -c '%i' "$cache_pip")"
pre_keep_manifest="$(manifest "$cache_keep")"
pre_omp_manifest="$(manifest "$omp")"
pre_browser_manifest="$(manifest "$cache_browser")"

run_migrate() { as_root "$script" --device "$loop" --mount-device "$loop" --fs-label cache-test --parent "$root/home" --parent "$share" "$@"; }
steam_local_root="$h/.local/share/Steam"
steam_local_apps="$steam_local_root/steamapps"
steam_share_root="$share/SteamLibrary"
steam_share_apps="$steam_share_root/steamapps"
steam_local_paths=(
  "$steam_local_apps/common"
  "$steam_local_apps/shadercache"
  "$steam_local_apps/downloading"
  "$steam_local_apps/workshop/content"
)
steam_share_paths=(
  "$steam_share_apps/common"
  "$steam_share_apps/shadercache"
  "$steam_share_apps/downloading"
  "$steam_share_apps/workshop/content"
)
steam_targets=("${steam_local_paths[@]}" "${steam_share_paths[@]}")
mkdir -p "${steam_local_paths[@]}" \
  "$steam_local_apps/compatdata/prefix" "$steam_local_apps/workshop" \
  "$steam_local_root/userdata" "$steam_local_root/config" \
  "$steam_share_apps/common" "$steam_share_apps/shadercache" "$steam_share_apps/downloading"
for path in "${steam_local_paths[@]}" "${steam_share_paths[@]:0:3}"; do
  printf 're-downloadable\n' >"$path/game-content.txt"
done
printf 'saved game\n' >"$steam_local_apps/compatdata/prefix/savedata"
printf 'userdata\n' >"$steam_local_root/userdata/state.vdf"
printf 'config\n' >"$steam_local_root/config/config.vdf"
printf 'manifest\n' >"$steam_local_apps/appmanifest-test.acf"
printf 'workshop manifest\n' >"$steam_local_apps/workshop/appworkshop_test.acf"
printf 'secondary manifest\n' >"$steam_share_apps/appmanifest-test.acf"
as_root chown -R 1000:100 "$steam_local_root" "$steam_share_root"
steam_local_before="$(manifest "$steam_local_root")"
steam_share_before="$(manifest "$steam_share_root")"
run_migrate_steam() {
  as_root "$script" "${migration_args[@]}" --device "$loop" --mount-device "$loop" --fs-label cache-test \
    --parent "$root/home" --parent "$share" \
    --require-stopped-process steam --require-stopped-process steamwebhelper "$@"
}
for process in steam steamwebhelper; do
  : >"$active_process_dir/$process"
  if out="$(run_migrate_steam "${steam_targets[@]}" 2>&1)"; then
    fail "Steam migration accepted running process $process"
  fi
  case "$out" in
    *"required process '$process' is running"*) : ;;
    *) fail "Steam process refusal did not name $process: $out" ;;
  esac
  for path in "${steam_targets[@]}"; do
    if as_root btrfs subvolume show "$path" >/dev/null 2>&1; then
      fail "active Steam refusal converted $path"
    fi
  done
  [ "$(manifest "$steam_local_root")" = "$steam_local_before" ] || fail "active Steam refusal changed home Steam data"
  [ "$(manifest "$steam_share_root")" = "$steam_share_before" ] || fail "active Steam refusal changed shared Steam data"
  rm -f "$active_process_dir/$process"
done
run_migrate_steam "${steam_targets[@]}" >/dev/null
for path in "${steam_targets[@]}"; do
  as_root btrfs subvolume show "$path" >/dev/null 2>&1 || fail "stopped Steam path was not migrated: $path"
done
[ "$(stat -c '%u:%g %a' "$(dirname "${steam_share_paths[3]}")")" = "$(stat -c '%u:%g %a' "$steam_share_apps")" ] ||
  fail "new nested workshop parent did not adopt its Steam library parent metadata"
for protected in \
  "$steam_local_apps/compatdata/prefix/savedata" \
  "$steam_local_root/userdata/state.vdf" \
  "$steam_local_root/config/config.vdf" \
  "$steam_local_apps/appmanifest-test.acf" \
  "$steam_local_apps/workshop/appworkshop_test.acf" \
  "$steam_share_apps/appmanifest-test.acf"; do
  [ -f "$protected" ] || fail "Steam data/manifests must stay in the backed-up parent: $protected"
done
pass "manual Steam migration refuses running steam/steamwebhelper, migrates both libraries, and preserves save/config/manifest paths"


refuse() {
  local expected="$1"
  shift
  local out
  if out="$(run_migrate "$@" 2>&1)"; then
    fail "migration accepted $* (expected: $expected)"
  fi
  case "$out" in
    *"$expected"*) : ;;
    *) fail "refusal for $* did not report '$expected': $out" ;;
  esac
}

# ── 1. busy caches refuse migration ───────────────────────────────────
busy_fd="$h/.cache/spare-busy-fd"
busy_cwd="$h/.cache/spare-busy-cwd"
mkdir -p "$busy_fd" "$busy_cwd"
printf 'held\n' > "$busy_fd/held.txt"
printf 'cwd\n' > "$busy_cwd/cwd.txt"
chown -R 1000:100 "$busy_fd" "$busy_cwd"

bash -c "exec 3<\"$busy_fd/held.txt\"; sleep 60" &
holders+=("$!")
(
  cd "$busy_cwd"
  exec sleep 60
) &
holders+=("$!")
sleep 1

for kind in fd cwd; do
  case "$kind" in
    fd) target="$busy_fd" ;;
    cwd) target="$busy_cwd" ;;
  esac
  if out="$(run_migrate "$target" 2>&1)"; then
    fail "migration accepted a cache with an active $kind writer"
  fi
  case "$out" in
    *'refusing to migrate busy path'*) : ;;
    *) fail "busy ($kind) refusal did not come from the writer guard: $out" ;;
  esac
  if as_root btrfs subvolume show "$target" >/dev/null 2>&1; then
    fail "busy cache (${kind}) was converted into a subvolume"
  fi
 [ ! -e "$(dirname "$target")/.$(basename "$target")${rollback_suffix}" ] || fail "busy cache (${kind}) left rollback material"
 [ ! -e "$(dirname "$target")/.$(basename "$target")${staging_suffix}" ] || fail "busy cache (${kind}) left staging material"
done

pass "a busy cache (open fd and cwd) refuses migration and stays untouched"

for pid in "${holders[@]}"; do kill "$pid" 2>/dev/null; done
wait 2>/dev/null
holders=()

# ── 2. device / label mismatches refuse migration ─────────────────────
if out="$(as_root "$script" --device "$loop_other" --mount-device "$loop" --fs-label cache-test --parent "$root/home" --parent "$share" "$cache_pip" 2>&1)"; then
  fail "migration accepted a filesystem on a different device than declared"
fi
case "$out" in
  *"not on declared root disk"*) : ;;
  *) fail "device mismatch was not reported as such: $out" ;;
esac

refuse 'label mismatch' "$cache_pip" --fs-label wrong-label

if as_root btrfs subvolume show "$cache_pip" >/dev/null 2>&1; then
  fail "a refused run still converted the cache"
fi
[ "$(manifest "$cache_pip")" = "$pre_pip_manifest" ] || fail "a refused run changed the cache"
pass "device and label mismatches are refused with nothing changed"

# ── 3. structural refusals ────────────────────────────────────────────
symlink="$h/.cache/spare-symlink"
ln -s /tmp "$symlink"
refuse 'symlink' "$symlink"
[ -L "$symlink" ] || fail "the migration replaced the symlink"

# Regression: `btrfs subvolume show` follows symlinks, so a symlink whose
# target IS a subvolume must still be refused, not skipped as "already a
# subvolume".
as_root btrfs subvolume create "$root/spare-subvol" >/dev/null
symlink_sub="$h/.cache/spare-symlink-subvol"
ln -s "$root/spare-subvol" "$symlink_sub"
refuse 'symlink' "$symlink_sub"
[ -L "$symlink_sub" ] || fail "the migration replaced the subvolume-pointing symlink"

# A foreign filesystem mounted at the cache path is refused by the
# identity validation (never by anything later, and never silently).
mountpoint="$h/.cache/spare-mount"
mkdir -p "$mountpoint"
as_root mount -t tmpfs tmpfs "$mountpoint"
refuse 'not Btrfs' "$mountpoint"
as_root umount "$mountpoint"
[ ! -e "$(dirname "$mountpoint")/.$(basename "$mountpoint")${staging_suffix}" ] || fail "migration left staging for a mount point"

# A bind mount of a plain directory IS on the declared btrfs, so only the
# mount-point guard can catch it.
bind_src="$h/.cache/spare-bind-src"
bind_dst="$h/.cache/spare-bind"
mkdir -p "$bind_src" "$bind_dst"
printf 'bind\n' > "$bind_src/data.txt"
as_root mount --bind "$bind_src" "$bind_dst"
refuse 'mount point' "$bind_dst"
as_root umount "$bind_dst"
[ ! -e "$(dirname "$bind_dst")/.$(basename "$bind_dst")${staging_suffix}" ] || fail "migration left staging for a bind mount"

# Identity validation must precede every no-op/adoption branch: a
# root-owned boundary living on ANOTHER filesystem is refused and left
# completely alone (owner, contents, inode).
other_h="$other_root/home/nori"
as_root mkdir -p "$other_h/.cache"
wrong_device="$other_h/.cache/spare-wrong-device"
as_root btrfs subvolume create "$wrong_device" >/dev/null
as_root install -m 0644 -o 0 -g 0 /dev/null "$wrong_device/root-owned.txt"
as_root sh -c "printf 'root\n' > '$wrong_device/root-owned.txt'"
wrong_before_meta="$(stat -c '%u:%g %a %i' "$wrong_device")"
wrong_before_manifest="$(manifest "$wrong_device")"
# The configured parent path includes the foreign subvolume; identity validation must refuse it.
if out="$(as_root "$script" --device "$loop" --mount-device "$loop" --fs-label cache-test --parent "$other_root/home" "$wrong_device" 2>&1)"; then
  fail "migration accepted a boundary on a different filesystem than declared"
fi
case "$out" in
  *'not declared partition'*) : ;;
  *) fail "wrong-device refusal did not come from identity validation: $out" ;;
esac
[ "$(stat -c '%u:%g %a %i' "$wrong_device")" = "$wrong_before_meta" ] ||
  fail "a refused wrong-device boundary changed ownership/inode (must not be adopted)"
[ "$(manifest "$wrong_device")" = "$wrong_before_manifest" ] ||
  fail "a refused wrong-device boundary had its contents changed"

rollback="$h/.cache/spare-rollback"
rollback_path="$(dirname "$rollback")/.$(basename "$rollback")${rollback_suffix}"
mkdir -p "$rollback" "$rollback_path"
refuse 'rollback subvolume already exists' "$rollback"
[ ! -e "$(dirname "$rollback")/.$(basename "$rollback")${staging_suffix}" ] ||
  fail "the migration created staging despite existing rollback material"

stale="$h/.cache/spare-stale"
staging_path="$(dirname "$stale")/.$(basename "$stale")${staging_suffix}"
mkdir -p "$stale" "$staging_path"
refuse 'stale staging path exists' "$stale"
converted="$h/.cache/spare-converted"
as_root btrfs subvolume create "$converted" >/dev/null
converted_staging="$(dirname "$converted")/.$(basename "$converted")$staging_suffix"
mkdir "$converted_staging"
printf 'preserve-unresolved-original\n' > "$converted_staging/original.txt"
refuse 'stale staging path exists' "$converted"
[ "$(cat "$converted_staging/original.txt")" = preserve-unresolved-original ] ||
  fail "retry discarded unresolved original beside a converted live subvolume"
pass "a converted target with preserved plain staging still refuses retry"
pass "symlink (incl. one pointing at a subvolume), foreign mount, bind mount, wrong-device boundary, rollback and stale-staging guards refused"

# ── 4. an incomplete lsof scan is a blocker ───────────────────────────
# lsof exits 1 both for "nothing found" and for its own failures, so the
# guard must never read a failed, empty scan as healthy. Both shims below
# produce no output; both must refuse.
shim_root="$work/shims"
mkdir -p "$shim_root/anomaly" "$shim_root/zero" "$shim_root/second"
cat > "$shim_root/anomaly/lsof" <<'SHIM'
#!/usr/bin/env bash
exit 7
SHIM
cat > "$shim_root/zero/lsof" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
# Free on the first scan, busy on the re-check before the cutover.
cat > "$shim_root/second/lsof" <<'SHIM'
#!/usr/bin/env bash
count="$(cat "$LSOF_SHIM_COUNTER" 2>/dev/null || printf 0)"
count=$((count + 1))
printf '%s' "$count" > "$LSOF_SHIM_COUNTER"
if [ "$count" -ge 2 ]; then
  printf '424242\n'
fi
exit 1
SHIM
chmod +x "$shim_root"/*/lsof

for mode in anomaly zero; do
  target="$h/.cache/spare-lsof-$mode"
  mkdir -p "$target"
  printf 'lsof-%s\n' "$mode" > "$target/data.txt"
  chown -R 1000:100 "$target"
  before="$(manifest "$target")"
  if out="$(sudo -n env "PATH=$shim_root/$mode:$PATH" "$script" "${migration_args[@]}" --device "$loop" --mount-device "$loop" --fs-label cache-test --parent "$root/home" --parent "$share" "$target" 2>&1)"; then
    fail "an incomplete lsof scan ($mode) was treated as a free cache"
  fi
  case "$out" in
    *'lsof'*) : ;;
    *) fail "lsof $mode refusal did not name the scan: $out" ;;
  esac
[ "$(manifest "$target")" = "$before" ] || fail "lsof $mode refusal changed the cache"
[ ! -e "$(dirname "$target")/.$(basename "$target")${rollback_suffix}" ] || fail "lsof $mode refusal left rollback material"
done
pass "an lsof scan that fails or returns success without listing a file is refused"

# ── 5. the pre-cutover re-check discards only the copied staging ───────
second="$h/.cache/spare-second-check"
mkdir -p "$second"
printf 'second\n' > "$second/data.txt"
chown -R 1000:100 "$second"
second_before="$(manifest "$second")"
counter="$work/lsof-counter"
printf 0 > "$counter"
if out="$(sudo -n env "PATH=$shim_root/second:$PATH" LSOF_SHIM_COUNTER="$counter" "$script" "${migration_args[@]}" --device "$loop" --mount-device "$loop" --fs-label cache-test --parent "$root/home" --parent "$share" "$second" 2>&1)"; then
  fail "the writer re-check before the cutover did not block a writer that appeared mid-copy"
fi
case "$out" in
  *'refusing to swap busy path'*) : ;;
  *) fail "the mid-copy writer did not block the cutover: $out" ;;
esac
if as_root btrfs subvolume show "$second" >/dev/null 2>&1; then
  fail "the blocked cutover still converted the cache"
fi
[ ! -e "$(dirname "$second")/.$(basename "$second")${staging_suffix}" ] || fail "blocked cutover left staging behind"
[ "$(manifest "$second")" = "$second_before" ] || fail "blocked cutover changed the original"
[ ! -e "$(dirname "$second")/.$(basename "$second")${rollback_suffix}" ] || fail "blocked cutover left rollback material"
pass "a mid-copy writer blocks cutover, discards only staging, and leaves the original untouched"

# ── 6. an absent cache directory gets its boundary up front ───────────
created="$h/.cache/spare-created"
run_migrate "$created" >/dev/null
as_root btrfs subvolume show "$created" >/dev/null 2>&1 ||
  fail "an absent cache path did not get a boundary created"
[ ! -e "$(dirname "$created")/.$(basename "$created")${rollback_suffix}" ] || fail "empty boundary left rollback material"
[ "$(stat -c '%u:%g %a' "$created")" = "$(stat -c '%u:%g %a' "$h/.cache")" ] ||
  fail "the created boundary did not adopt the cache parent's ownership/mode ($(meta "$created") vs $(meta "$h/.cache"))"
pass "an absent cache path is created as a boundary owned like the cache parent"

# ── 7. an install-time root-owned boundary adopts ownership ───────────
install_boundary="$h/.cache/spare-install"
as_root btrfs subvolume create "$install_boundary" >/dev/null
as_root install -m 0640 -o 1000 -g 100 /dev/null "$install_boundary/legacy.txt"
as_root sh -c "printf 'legacy\n' > '$install_boundary/legacy.txt'"
as_root chown 1000:100 "$install_boundary/legacy.txt"
legacy_before="$(manifest "$install_boundary/legacy.txt")"
[ "$(stat -c '%u:%g' "$install_boundary")" = "0:0" ] || fail "test precondition: boundary should start root-owned"
run_migrate "$install_boundary" >/dev/null
[ "$(stat -c '%u:%g' "$install_boundary")" = "$(stat -c '%u:%g' "$h/.cache")" ] ||
  fail "a root-owned install-time boundary did not adopt the derived ownership"
[ "$(manifest "$install_boundary/legacy.txt")" = "$legacy_before" ] ||
  fail "ownership adoption changed the boundary's contents (it must touch only the boundary directory)"
pass "a root-owned install-time boundary adopts derived ownership without touching contents"

# ── 8. migration preserves everything and atomically cuts over ────────
trace="$work/rename-trace.log"
as_root strace -f -e trace=renameat2,rename -o "$trace" "$script" \
  "${migration_args[@]}" \
  --device "$loop" --mount-device "$loop" --fs-label cache-test --parent "$root/home" --parent "$share" \
  "$cache_pip" "$cache_uv" "$cache_nix" "$projects" >/dev/null

for p in "$cache_pip" "$cache_uv" "$cache_nix" "$projects"; do
  as_root btrfs subvolume show "$p" >/dev/null 2>&1 || fail "$p is not a nested subvolume after migration"
 rollback_path="$(dirname "$p")/.$(basename "$p")${rollback_suffix}"
  as_root btrfs subvolume show "$rollback_path" >/dev/null 2>&1 || fail "read-only rollback subvolume missing for $p"
  [ "$(as_root btrfs property get -ts "$rollback_path" ro)" = "ro=true" ] || fail "rollback for $p is not read-only"
 [ ! -e "$(dirname "$p")/.$(basename "$p")${staging_suffix}" ] || fail "staging path remains for $p"
done

[ "$(manifest "$cache_pip")" = "$pre_pip_manifest" ] || fail "migrated cache contents/metadata differ from original"
[ "$(digest "$cache_pip")" = "$pre_pip_digest" ] || fail "migrated cache file contents differ from original"
[ "$(stat -c '%a %u %g %Y' "$cache_pip")" = "$pre_pip_meta" ] || fail "migrated cache directory metadata differs from original"
rollback_pip="$(dirname "$cache_pip")/.$(basename "$cache_pip")${rollback_suffix}"
[ "$(manifest "$rollback_pip")" = "$pre_pip_manifest" ] || fail "rollback snapshot differs from pre-migration tree"
[ ! -e "$(dirname "$cache_pip")/.$(basename "$cache_pip")${staging_suffix}" ] || fail "verified cutover left a plain staging duplicate"
[ "$(stat -c '%i' "$cache_pip")" != "$pre_pip_inode" ] || fail "cache path still holds pre-migration directory inode"
[ -f "$projects/app/README" ] && [ -f "$projects/local-only/notes" ] || fail "project data was not preserved"
[ "$(cat "$projects/local-only/notes")" = "local ignored/uncommitted data" ] || fail "local-only project data changed"
[ "$(manifest "$cache_keep")" = "$pre_keep_manifest" ] || fail "protected neighbouring directory changed"
[ "$(manifest "$omp")" = "$pre_omp_manifest" ] || fail "omp agent cache changed"
[ "$(manifest "$cache_browser")" = "$pre_browser_manifest" ] || fail "browser cache changed"
if as_root btrfs subvolume show "$cache_keep" >/dev/null 2>&1; then fail "protected neighbour became a subvolume"; fi
pass "migration preserves data/metadata, keeps read-only nested rollback, and removes only the verified plain duplicate"

# ── 9. the cutover is a single atomic exchange ────────────────────────
[ -s "$trace" ] || fail "the strace trace is empty — the cutover was not observed"
for p in "$cache_pip" "$cache_uv" "$cache_nix"; do
  if ! grep -F "\"$p\"" "$trace" | grep -q 'RENAME_EXCHANGE'; then
    fail "no RENAME_EXCHANGE observed for $p in the trace"
  fi
  # Any other rename naming the cache path would be the gap-creating move
  # (path briefly absent) or the nesting move this regression exists for.
  if grep -F "\"$p\"" "$trace" | grep -v 'RENAME_EXCHANGE' | grep -q .; then
    fail "a rename touched $p without RENAME_EXCHANGE: $(grep -F "\"$p\"" "$trace" | grep -v RENAME_EXCHANGE | head -2)"
  fi
done
pass "the cutover is one renameat2(RENAME_EXCHANGE) per cache path — no gap, no nesting move"

# ── 10. idempotent ────────────────────────────────────────────────────
run_migrate "$cache_pip" "$cache_uv" "$cache_nix" >/dev/null
[ "$(manifest "$cache_pip")" = "$pre_pip_manifest" ] || fail "a second run changed the migrated cache"
[ "$(stat -c '%u:%g' "$cache_pip")" = "$(stat -c '%u:%g' "$h/.cache")" ] ||
  fail "a second run disturbed the migrated boundary ownership"
pass "a second run is a no-op"

# ── 11. snapshots omit nested cache and project subvolumes ──────────
snap="$root/snap-home"
snap_share="$root/snap-share"
as_root btrfs subvolume snapshot -r "$root/home" "$snap" >/dev/null
as_root btrfs subvolume snapshot -r "$share" "$snap_share" >/dev/null
[ -d "$snap/nori/.cache/pip" ] || fail "home snapshot lost the cache path entirely"
[ -z "$(ls -A "$snap/nori/.cache/pip")" ] || fail "home snapshot includes nested cache contents"
[ -f "$snap/nori/.cache/keepme/protected.txt" ] || fail "protected home neighbour missing from snapshot"
[ -f "$snap/nori/.omp/agent/cache/omp.txt" ] || fail "OMP agent cache missing from snapshot"
[ -d "$snap_share/projects" ] || fail "share snapshot lost the projects path entirely"
[ -z "$(ls -A "$snap_share/projects")" ] || fail "share snapshot includes nested project contents"
[ -f "$share/projects-neighbour.txt" ] || fail "protected share neighbour missing from source"
pass "snapshots omit nested cache and project data while preserving parent data"
for path in "${steam_local_paths[@]}"; do
  snapshot_path="$snap/nori/${path#"$h"/}"
  [ -d "$snapshot_path" ] || fail "home snapshot lost Steam path $path"
  [ -z "$(ls -A "$snapshot_path")" ] || fail "home snapshot includes Steam game content at $path"
done
for path in "${steam_share_paths[@]}"; do
  snapshot_path="$snap_share/${path#"$share"/}"
  [ -d "$snapshot_path" ] || fail "share snapshot lost Steam path $path"
  [ -z "$(ls -A "$snapshot_path")" ] || fail "share snapshot includes Steam game content at $path"
done
[ -f "$snap/nori/.local/share/Steam/steamapps/compatdata/prefix/savedata" ] || fail "home snapshot omitted Proton save data"
[ -f "$snap/nori/.local/share/Steam/userdata/state.vdf" ] || fail "home snapshot omitted Steam userdata"
[ -f "$snap/nori/.local/share/Steam/config/config.vdf" ] || fail "home snapshot omitted Steam config"
[ -f "$snap/nori/.local/share/Steam/steamapps/appmanifest-test.acf" ] || fail "home snapshot omitted Steam app manifest"
[ -f "$snap/nori/.local/share/Steam/steamapps/workshop/appworkshop_test.acf" ] || fail "home snapshot omitted workshop manifest"
[ -f "$snap_share/SteamLibrary/steamapps/appmanifest-test.acf" ] || fail "share snapshot omitted secondary-library manifest"
pass "parent snapshots omit Steam game content and preserve saves, config and manifests"

# ── 12. recursive Restic honors registry-derived exclusions ─────────
repo="$work/restic-repo"
pwfile="$work/restic-password"
printf 'subvolume-migration-test\n' > "$pwfile"
export RESTIC_CACHE_DIR="$work/restic-cache"
restic -r "$repo" --password-file "$pwfile" init >/dev/null
exclusions=()
while IFS= read -r excluded; do
  case "$excluded" in
    /home|/home/*) excluded="$root$excluded" ;;
    /srv/share|/srv/share/*) excluded="$share${excluded#/srv/share}" ;;
  esac
  exclusions+=(--exclude "$excluded")
done < <(jq -r ' .excludes[] ' <<<"$layout")
restic -r "$repo" --password-file "$pwfile" backup "${exclusions[@]}" "$root/home" "$share" >/dev/null
ls_output="$(restic -r "$repo" --password-file "$pwfile" ls latest)"
for excluded in "$cache_pip" "$cache_uv" "$cache_nix" "$projects" "${steam_targets[@]}"; do
  if printf '%s\n' "$ls_output" | awk -v p="$excluded" '$0 == p || index($0, p "/") == 1 { found = 1 } END { exit found ? 0 : 1 }'; then
    fail "recursive Restic backup included excluded path $excluded"
  fi
done
for target in "$cache_pip" "$cache_uv" "$cache_nix" "$projects" "${steam_targets[@]}"; do
  for suffix in "$staging_suffix" "$rollback_suffix"; do
    excluded="$(dirname "$target")/.$(basename "$target")$suffix"
    if printf '%s\n' "$ls_output" | awk -v p="$excluded" '$0 == p || index($0, p "/") == 1 { found = 1 } END { exit found ? 0 : 1 }'; then
      fail "recursive Restic backup included migration artifact $excluded"
    fi
  done
done
for protected in \
  "$steam_local_apps/compatdata/prefix/savedata" \
  "$steam_local_root/userdata/state.vdf" \
  "$steam_local_root/config/config.vdf" \
  "$steam_local_apps/appmanifest-test.acf" \
  "$steam_local_apps/workshop/appworkshop_test.acf" \
  "$steam_share_apps/appmanifest-test.acf"; do
  printf '%s\n' "$ls_output" | grep -qF "$protected" || fail "Restic omitted protected Steam state $protected"
done
printf '%s\n' "$ls_output" | grep -qF "$cache_keep/protected.txt" || fail "Restic dropped protected home neighbour"
printf '%s\n' "$ls_output" | grep -qF "$omp/omp.txt" || fail "Restic dropped OMP agent cache"
printf '%s\n' "$ls_output" | grep -qF "$cache_browser/entry" || fail "Restic dropped browser cache"
printf '%s\n' "$ls_output" | grep -qF "$share/projects-neighbour.txt" || fail "Restic dropped protected share neighbour"
pass "recursive Restic excludes cache/project/Steam game data and migration artifacts while keeping protected neighbours"

pass "all nested-subvolume migration checks passed"
