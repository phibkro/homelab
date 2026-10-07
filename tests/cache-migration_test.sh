#!/usr/bin/env bash
#
# Focused semantic test for the disposable-cache migration
# (src/infra/workstation/cache-migrate.sh) and for the mechanisms the
# cache separation relies on. Everything runs against real, disposable
# loop-backed Btrfs filesystems under a temp directory — never the live
# root, the live /home, a real cache, or a user process.
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
#   8. migration preserves contents, ownership, mode and timestamp,
#      keeps the original directory itself as rollback material (same
#      inode), and never nests the staging tree inside the cache path;
#   9. the cutover is one atomic renameat2(RENAME_EXCHANGE): the cache
#      path is never renamed away, so no gap exists for a new writer and
#      no plain-directory destination can swallow the staging tree;
#  10. a second run is a no-op;
#  11. a snapshot of the parent subvolume omits the nested cache
#      boundaries while a protected neighbouring directory stays;
#  12. a recursive restic backup of the parent with the derived
#      exclusion paths omits the caches and keeps that neighbour — the
#      production failure mode, since a nested subvolume is absent from
#      a snapshot but NOT from a live recursive walk.
#
# Usage: cache-migration_test.sh <path-to-cache-migrate.sh>
# Requires: sudo -n, btrfs-progs, GNU coreutils >= 9.1 (mv --exchange),
# strace, lsof, restic, findutils, util-linux, diffutils, gnused.
set -euo pipefail

script="${1:?usage: cache-migration_test.sh <path-to-cache-migrate.sh>}"
script="$(readlink -f -- "$script")"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

as_root() { sudo -n env "PATH=$PATH" "$@"; }

work="$(mktemp -d /tmp/nori-cache-migration-test.XXXXXX)"
img="$work/cache.img"
img_other="$work/other.img"
root="$work/fs"
other_root="$work/other"
loop=""
loop_other=""
holders=()

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

h="$root/home/nori"
cache_pip="$h/.cache/pip"
cache_uv="$h/.cache/uv"
cache_nix="$h/.cache/nix"
cache_keep="$h/.cache/keepme"
cache_browser="$h/.cache/chromium/Default/Cache"
omp="$h/.omp/agent/cache"

# The parent boundary a snapshot is taken of; the caches become nested
# subvolumes inside it when the migration runs.
as_root btrfs subvolume create "$root/home" >/dev/null
# Fixtures are created by the invoking (non-root) user so the migration is
# exercised against files it must preserve without owning.
as_root chown 1000:100 "$root/home"
mkdir -p "$cache_pip/subdir" "$cache_uv" "$cache_nix" "$cache_keep" "$cache_browser" "$omp"

printf 'alpha\n' > "$cache_pip/a.txt"
printf 'beta\n' > "$cache_pip/subdir/b.txt"
head -c 262144 /dev/urandom > "$cache_pip/blob.bin"
ln -s a.txt "$cache_pip/link"
printf 'uv\n' > "$cache_uv/u.txt"
printf 'nix\n' > "$cache_nix/n.txt"
printf 'keep\n' > "$cache_keep/protected.txt"
printf 'browser-state\n' > "$cache_browser/entry"
printf 'omp-agent-cache\n' > "$omp/omp.txt"
chmod 0751 "$cache_pip/subdir"
chmod 0640 "$cache_pip/a.txt"
chmod 0700 "$cache_pip"
chown -R 1000:100 "$h"
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

run_migrate() { as_root "$script" --device "$loop" --mount-device "$loop" --fs-label cache-test --home "$root/home" "$@"; }

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
    *'refusing to migrate a busy cache'*) : ;;
    *) fail "busy ($kind) refusal did not come from the writer guard: $out" ;;
  esac
  if as_root btrfs subvolume show "$target" >/dev/null 2>&1; then
    fail "busy cache (${kind}) was converted into a subvolume"
  fi
  [ ! -e "$target.pre-cache-separation" ] || fail "busy cache (${kind}) left rollback material behind"
  [ ! -e "$(dirname "$target")/.$(basename "$target").cache-migration-staging" ] ||
    fail "busy cache (${kind}) left a staging subvolume behind"
done
pass "a busy cache (open fd and cwd) refuses migration and stays untouched"

for pid in "${holders[@]}"; do kill "$pid" 2>/dev/null; done
wait 2>/dev/null
holders=()

# ── 2. device / label mismatches refuse migration ─────────────────────
if out="$(as_root "$script" --device "$loop_other" --mount-device "$loop" --fs-label cache-test --home "$root/home" "$cache_pip" 2>&1)"; then
  fail "migration accepted a filesystem on a different device than declared"
fi
case "$out" in
  *"not on the declared root disk"*) : ;;
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
refuse 'not btrfs' "$mountpoint"
as_root umount "$mountpoint"
[ ! -e "$mountpoint.pre-cache-separation" ] || fail "the migration touched a mount point"

# A bind mount of a plain directory IS on the declared btrfs, so only the
# mount-point guard can catch it.
bind_src="$h/.cache/spare-bind-src"
bind_dst="$h/.cache/spare-bind"
mkdir -p "$bind_src" "$bind_dst"
printf 'bind\n' > "$bind_src/data.txt"
as_root mount --bind "$bind_src" "$bind_dst"
refuse 'mount point' "$bind_dst"
as_root umount "$bind_dst"
[ ! -e "$bind_dst.pre-cache-separation" ] || fail "the migration touched a bind mount"

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
# --home matches the path so the home-path guard passes and the identity
# validation is what must refuse.
if out="$(as_root "$script" --device "$loop" --mount-device "$loop" --fs-label cache-test --home "$other_root/home" "$wrong_device" 2>&1)"; then
  fail "migration accepted a boundary on a different filesystem than declared"
fi
case "$out" in
  *'not from the declared home partition'*) : ;;
  *) fail "wrong-device refusal did not come from the identity validation: $out" ;;
esac
[ "$(stat -c '%u:%g %a %i' "$wrong_device")" = "$wrong_before_meta" ] ||
  fail "a refused wrong-device boundary changed ownership/inode (must not be adopted)"
[ "$(manifest "$wrong_device")" = "$wrong_before_manifest" ] ||
  fail "a refused wrong-device boundary had its contents changed"

rollback="$h/.cache/spare-rollback"
mkdir -p "$rollback" "$rollback.pre-cache-separation"
refuse 'rollback material already exists' "$rollback"
[ ! -e "$(dirname "$rollback")/.spare-rollback.cache-migration-staging" ] ||
  fail "the migration created staging despite existing rollback material"

stale="$h/.cache/spare-stale"
mkdir -p "$stale" "$h/.cache/.spare-stale.cache-migration-staging"
refuse 'stale staging' "$stale"
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
  if out="$(sudo -n env "PATH=$shim_root/$mode:$PATH" "$script" --device "$loop" --mount-device "$loop" --fs-label cache-test --home "$root/home" "$target" 2>&1)"; then
    fail "an incomplete lsof scan ($mode) was treated as a free cache"
  fi
  case "$out" in
    *'lsof'*) : ;;
    *) fail "lsof $mode refusal did not name the scan: $out" ;;
  esac
  [ "$(manifest "$target")" = "$before" ] || fail "lsof $mode refusal changed the cache"
  [ ! -e "$target.pre-cache-separation" ] || fail "lsof $mode refusal left rollback material"
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
if out="$(sudo -n env "PATH=$shim_root/second:$PATH" LSOF_SHIM_COUNTER="$counter" "$script" --device "$loop" --mount-device "$loop" --fs-label cache-test --home "$root/home" "$second" 2>&1)"; then
  fail "the writer re-check before the cutover did not block a writer that appeared mid-copy"
fi
case "$out" in
  *'refusing to swap a busy cache'*) : ;;
  *) fail "the mid-copy writer did not block the cutover: $out" ;;
esac
if as_root btrfs subvolume show "$second" >/dev/null 2>&1; then
  fail "the blocked cutover still converted the cache"
fi
[ ! -e "$h/.cache/.spare-second-check.cache-migration-staging" ] ||
  fail "the blocked cutover left its staging subvolume behind"
[ "$(manifest "$second")" = "$second_before" ] || fail "the blocked cutover changed the original"
[ ! -e "$second.pre-cache-separation" ] || fail "the blocked cutover left rollback material"
pass "a mid-copy writer blocks the cutover, its staging is discarded, the original is untouched"

# ── 6. an absent cache directory gets its boundary up front ───────────
created="$h/.cache/spare-created"
run_migrate "$created" >/dev/null
as_root btrfs subvolume show "$created" >/dev/null 2>&1 ||
  fail "an absent cache path did not get a boundary created"
[ ! -e "$created.pre-cache-separation" ] || fail "an empty boundary left rollback material"
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

# ── 8. migration preserves everything, atomically ─────────────────────
trace="$work/rename-trace.log"
as_root strace -f -e trace=renameat2,rename -o "$trace" "$script" \
  --device "$loop" --mount-device "$loop" --fs-label cache-test --home "$root/home" \
  "$cache_pip" "$cache_uv" "$cache_nix" >/dev/null

for p in "$cache_pip" "$cache_uv" "$cache_nix"; do
  as_root btrfs subvolume show "$p" >/dev/null 2>&1 || fail "$p is not a nested subvolume after migration"
  [ -d "$p.pre-cache-separation" ] || fail "rollback material missing for $p"
  if as_root btrfs subvolume show "$p.pre-cache-separation" >/dev/null 2>&1; then
    fail "rollback material for $p is a subvolume, not the original directory"
  fi
  [ ! -e "$(dirname "$p")/.$(basename "$p").cache-migration-staging" ] ||
    fail "staging subvolume left behind for $p"
  [ ! -e "$p/.$(basename "$p").cache-migration-staging" ] ||
    fail "the staging tree ended up nested inside the cache path $p"
done

[ "$(manifest "$cache_pip")" = "$pre_pip_manifest" ] || fail "migrated cache contents/metadata differ from the original"
[ "$(digest "$cache_pip")" = "$pre_pip_digest" ] || fail "migrated cache file contents differ from the original"
[ "$(stat -c '%a %u %g %Y' "$cache_pip")" = "$pre_pip_meta" ] || fail "migrated cache directory metadata differs from the original"
[ "$(manifest "$cache_pip.pre-cache-separation")" = "$pre_pip_manifest" ] ||
  fail "rollback copy differs from the pre-migration tree"
# The rollback directory must be the ORIGINAL directory itself (same
# inode), which is what the exchange leaves behind — not a copy.
[ "$(stat -c '%i' "$cache_pip.pre-cache-separation")" = "$pre_pip_inode" ] ||
  fail "rollback material is not the original directory (inode changed)"
[ "$(stat -c '%i' "$cache_pip")" != "$pre_pip_inode" ] ||
  fail "the cache path still holds the pre-migration directory"
[ "$(manifest "$cache_keep")" = "$pre_keep_manifest" ] || fail "protected neighbouring directory changed"
[ "$(manifest "$omp")" = "$pre_omp_manifest" ] || fail "the omp agent cache changed"
[ "$(manifest "$cache_browser")" = "$pre_browser_manifest" ] || fail "browser cache directory changed"
if as_root btrfs subvolume show "$cache_keep" >/dev/null 2>&1; then
  fail "a protected neighbouring directory was turned into a subvolume"
fi
pass "migration preserves contents/metadata and keeps the original directory as rollback material"

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

# ── 11. parent snapshot omits the nested caches ───────────────────────
snap="$root/snap-home"
as_root btrfs subvolume snapshot -r "$root/home" "$snap" >/dev/null
[ -d "$snap/nori/.cache/pip" ] || fail "the parent snapshot lost the cache path entirely"
[ -z "$(ls -A "$snap/nori/.cache/pip")" ] || fail "the nested cache subvolume leaked its contents into the parent snapshot"
[ -f "$snap/nori/.cache/keepme/protected.txt" ] || fail "the protected neighbour is missing from the parent snapshot"
[ -f "$snap/nori/.omp/agent/cache/omp.txt" ] || fail "the omp agent cache is missing from the parent snapshot"
pass "the parent snapshot omits the nested caches and keeps protected neighbours"

# ── 12. recursive restic backup with derived exclusions ───────────────
repo="$work/restic-repo"
pwfile="$work/restic-password"
printf 'cache-migration-test\n' > "$pwfile"
export RESTIC_CACHE_DIR="$work/restic-cache"
restic -r "$repo" --password-file "$pwfile" init >/dev/null
restic -r "$repo" --password-file "$pwfile" backup \
  --exclude "$cache_pip" --exclude "$cache_uv" --exclude "$cache_nix" \
  "$root/home" >/dev/null
ls_output="$(restic -r "$repo" --password-file "$pwfile" ls latest)"
for excluded in "$cache_pip" "$cache_uv" "$cache_nix"; do
  # Match the path itself or a descendant — not merely a prefix, so the
  # preserved rollback directory (<path>.pre-cache-separation) does not
  # trip the assertion.
  if printf '%s\n' "$ls_output" | awk -v p="$excluded" '$0 == p || index($0, p "/") == 1 { found = 1 } END { exit found ? 0 : 1 }'; then
    fail "recursive restic backup included the excluded cache $excluded"
  fi
done
printf '%s\n' "$ls_output" | grep -qF "$cache_pip.pre-cache-separation/a.txt" ||
  fail "recursive restic backup dropped the preserved rollback material"
printf '%s\n' "$ls_output" | grep -qF "$cache_keep/protected.txt" ||
  fail "recursive restic backup dropped the protected neighbour"
printf '%s\n' "$ls_output" | grep -qF "$omp/omp.txt" ||
  fail "recursive restic backup dropped the omp agent cache"
printf '%s\n' "$ls_output" | grep -qF "$cache_browser/entry" ||
  fail "recursive restic backup dropped the browser cache directory"
pass "recursive restic backup honours the derived exclusions and keeps protected neighbours"

pass "all cache-separation checks passed"
