#!/usr/bin/env bash
# Real-filesystem/subprocess fixture for services/music-ingest.
# It deliberately never touches /mnt/media or a live service.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../ingest.sh"
root="$(mktemp -d /tmp/music-ingest-runtime.XXXXXX)"
trap 'rm -rf -- "$root"' EXIT

staging="$root/staging"
master="$root/master"
inflight="$root/inflight"
mkdir -p -- "$staging" "$master" "$inflight"

if ! command -v b3sum >/dev/null 2>&1; then
  echo "music-ingest fixture: b3sum is required (run through devenv or nix shell)" >&2
  exit 1
fi

pass=0
fail=0
check() {
  local description="$1"
  shift
  if "$@"; then
    printf '  ✓ %s\n' "$description"
    pass=$((pass + 1))
  else
    printf '  ✗ %s\n' "$description" >&2
    fail=$((fail + 1))
  fi
}
write_file() {
  mkdir -p -- "$(dirname "$1")"
  printf '%s' "$2" >"$1"
}
age() { touch -d '2 hours ago' -- "$1"; }
content_equals() { [ "$(cat "$1")" = "$2" ]; }
has_suffixed_file() { [ -n "$(find "$1" -maxdepth 1 -type f -name 'file.flac.*' -print -quit)" ]; }
has_stale_temp() { [ -n "$(find "$1" -maxdepth 1 -type f -name '.music-ingest.*' -print -quit)" ]; }
no_stale_temp() { ! has_stale_temp "$1"; }
no_stale_temp_anywhere() { [ -z "$(find "$1" -type f -name '.music-ingest.*' -print -quit)" ]; }
run_ingest() {
  set +e
  MUSIC_INGEST_STAGING="$staging" \
    MUSIC_INGEST_MASTER="$master" \
    MUSIC_INGEST_INFLIGHT="$inflight" \
    MUSIC_INGEST_STABILITY_SECONDS=60 \
    bash "$script" >"$root/stdout" 2>"$root/stderr"
  rc=$?
  set -e
  return "$rc"
}

echo '=== basic ownership, guards, dedupe, conflict ==='
write_file "$staging/Artist/Album/stable.FLAC" 'stable'; age "$staging/Artist/Album/stable.FLAC"
write_file "$staging/Artist/Album/folder.JPG" 'art'; age "$staging/Artist/Album/folder.JPG"
write_file "$staging/Hidden/.cover.jpg" 'hidden'; age "$staging/Hidden/.cover.jpg"
write_file "$staging/Fresh/fresh.flac" 'fresh'
write_file "$staging/Temp/live.flac" 'temp'; age "$staging/Temp/live.flac"
: >"$staging/Temp/~syncthing~live.flac.tmp"
write_file "$master/Duplicate/file.flac" 'duplicate'
write_file "$staging/Duplicate/file.flac" 'duplicate'; age "$staging/Duplicate/file.flac"
write_file "$master/Conflict/file.flac" 'master';
write_file "$staging/Conflict/file.flac" 'staging'; age "$staging/Conflict/file.flac"

if run_ingest; then rc=0; else rc=$?; fi
check 'stable FLAC publishes and source path is removed' test -f "$master/Artist/Album/stable.FLAC"
check 'owned source is gone after durable publication' test ! -e "$staging/Artist/Album/stable.FLAC"
check 'case-insensitive art publishes' test -f "$master/Artist/Album/folder.JPG"
check 'hidden path remains untouched' test -f "$staging/Hidden/.cover.jpg"
check 'fresh file remains in staging' test -f "$staging/Fresh/fresh.flac"
check 'Syncthing temp sibling preserves source' test -f "$staging/Temp/live.flac"
check 'duplicate removes only claimed source' test ! -e "$staging/Duplicate/file.flac"
check 'duplicate leaves canonical bytes' content_equals "$master/Duplicate/file.flac" duplicate
check 'different canonical content returns conflict status' test "$rc" -eq 3
check 'conflict leaves canonical content' content_equals "$master/Conflict/file.flac" master
check 'conflict claim is quarantined' test -f "$staging/.conflicts/Conflict/file.flac"
check 'conflict source path is gone after quarantine' test ! -e "$staging/Conflict/file.flac"

echo '=== post-claim stability revalidation ==='
write_file "$staging/FreshSwap/file.flac" 'before-swap'; age "$staging/FreshSwap/file.flac"
swap_shim="$root/swap-bin"
swap_signal="$root/swap-done"
real_mv="$(command -v mv)"
mkdir -p -- "$swap_shim"
write_file "$swap_shim/mv" "#!/bin/sh
if [ \"\${4:-}\" = \"$inflight/FreshSwap/file.flac\" ] && [ ! -e \"$swap_signal\" ]; then
  printf '%s' 'after-swap' >\"$root/fresh-swap-replacement\"
  \"$real_mv\" -fT -- \"$root/fresh-swap-replacement\" \"$staging/FreshSwap/file.flac\"
  : >\"$swap_signal\"
fi
exec \"$real_mv\" \"\$@\"
"
chmod +x -- "$swap_shim/mv"
set +e
PATH="$swap_shim:$PATH" MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$root/swap.stdout" 2>"$root/swap.stderr"
swap_rc=$?
set -e
check 'fresh replacement is reached through real atomic rename' test -e "$swap_signal"
check 'fresh swapped inode is held for its own stability window' test "$swap_rc" -eq 0
check 'fresh swapped inode is recoverable as a claim' content_equals "$inflight/FreshSwap/file.flac" after-swap
check 'fresh swapped inode is not published early' test ! -e "$master/FreshSwap/file.flac"
check 'fresh swapped claim retains ownership marker' test -f "$inflight/FreshSwap/file.flac.owner"
touch -d '2 hours ago' -- "$inflight/FreshSwap/file.flac"
if run_ingest; then rc=0; else rc=$?; fi
check 'post-claim stability claim recovers after aging' test "$rc" -eq 0
check 'aged swapped claim publishes' content_equals "$master/FreshSwap/file.flac" after-swap
check 'aged swapped claim is removed' test ! -e "$inflight/FreshSwap/file.flac" -a ! -e "$inflight/FreshSwap/file.flac.owner"

echo '=== recovered claim and replacement after claim ==='
write_file "$inflight/Recovered/track.flac" 'recovered'
write_file "$staging/Replacement/track.flac" 'old-source'; age "$staging/Replacement/track.flac"

# A watcher waits for the real atomic claim to appear, then creates a new
# Syncthing version at the original path. The production script has no test
# hook; this is a real concurrent subprocess synchronization point.
watcher() {
  local claimed="$inflight/Replacement/track.flac"
  for _ in $(seq 1 200); do
    if [ -f "$claimed" ]; then
      write_file "$staging/Replacement/track.flac" 'new-source'
      age "$staging/Replacement/track.flac"
      return 0
    fi
    sleep 0.01
  done
  return 1
}
watcher & watcher_pid=$!
if run_ingest; then rc=0; else rc=$?; fi
wait "$watcher_pid"
check 'recovered inflight claim publishes' test -f "$master/Recovered/track.flac"
check 'recovered claim is removed after publication' test ! -e "$inflight/Recovered/track.flac"
check 'replacement remains at original staging path' test -f "$staging/Replacement/track.flac"
check 'replacement bytes are never deleted by current run' content_equals "$staging/Replacement/track.flac" new-source
check 'claimed old bytes publish' content_equals "$master/Replacement/track.flac" old-source

echo '=== pre-existing claim collision and quarantine no-clobber ==='
write_file "$inflight/Collision/file.flac" 'claimed-copy'
write_file "$staging/Collision/file.flac" 'normal-copy'; age "$staging/Collision/file.flac"
if run_ingest; then rc=0; else rc=$?; fi
check 'existing claim plus source fails the run' test "$rc" -eq 1
check 'claim collision retains inflight copy' test -f "$inflight/Collision/file.flac"
check 'claim collision retains staging copy' test -f "$staging/Collision/file.flac"
rm -f -- "$staging/Collision/file.flac"
if run_ingest; then rc=0; else rc=$?; fi
check 'collision can be recovered once source is removed' test "$rc" -eq 0
check 'recovered collision claim publishes' test -f "$master/Collision/file.flac"

write_file "$master/Quarantine/file.flac" 'canonical-copy'
write_file "$staging/.conflicts/Quarantine/file.flac" 'earlier-conflict'
write_file "$inflight/Quarantine/file.flac" 'new-conflict'
if run_ingest; then rc=0; else rc=$?; fi
check 'conflict with occupied quarantine returns conflict status' test "$rc" -eq 3
check 'occupied quarantine is never overwritten' content_equals "$staging/.conflicts/Quarantine/file.flac" earlier-conflict
check 'second conflict gets a deterministic suffixed quarantine file' has_suffixed_file "$staging/.conflicts/Quarantine"
check 'quarantine conflict leaves no inflight claim' test ! -e "$inflight/Quarantine/file.flac"

echo '=== interrupted copy retains claim and recovers ==='
write_file "$staging/Interrupted/file.flac" 'interrupt-me'; age "$staging/Interrupted/file.flac"
real_cp="$(command -v cp)"
shim="$root/bin"
mkdir -p -- "$shim"
write_file "$shim/cp" "#!/bin/sh
if [ \"\${2:-}\" = \"$inflight/Interrupted/file.flac\" ]; then
  exit 77
fi
exec \"$real_cp\" \"\$@\"
"
chmod +x -- "$shim/cp"
set +e
PATH="$shim:$PATH" MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$root/interrupted.stdout" 2>"$root/interrupted.stderr"
interrupted_rc=$?
set -e
check 'interrupted copy fails the run' test "$interrupted_rc" -eq 1
check 'interrupted copy leaves durable claim' test -f "$inflight/Interrupted/file.flac"
check 'interrupted copy does not publish partial destination' test ! -e "$master/Interrupted/file.flac"
rm -f -- "$shim/cp"
if run_ingest; then rc=0; else rc=$?; fi
check 'next run recovers interrupted claim' test "$rc" -eq 0
check 'recovered interrupted file is published' test -f "$master/Interrupted/file.flac"
check 'recovered interrupted claim is removed' test ! -e "$inflight/Interrupted/file.flac"

echo '=== hidden supplied roots still recover claims and filter descendants ==='
hidden_root="$root/hidden-root"
hidden_staging="$hidden_root/.staging-root"
hidden_inflight="$hidden_root/.inflight-root"
hidden_master="$hidden_root/.master-root"
mkdir -p -- "$hidden_staging" "$hidden_inflight" "$hidden_master"
write_file "$hidden_inflight/Interrupted/file.flac" 'hidden-inflight-claim'; age "$hidden_inflight/Interrupted/file.flac"
write_file "$hidden_staging/Fresh/file.flac" 'hidden-root-source'; age "$hidden_staging/Fresh/file.flac"
write_file "$hidden_staging/.hidden-child/ignored.flac" 'hidden-child'
hidden_real_cp="$(command -v cp)"
hidden_shim="$hidden_root/bin"
mkdir -p -- "$hidden_shim"
write_file "$hidden_shim/cp" "#!/bin/sh
if [ \"\${2:-}\" = \"$hidden_inflight/Interrupted/file.flac\" ]; then
  exit 77
fi
exec \"$hidden_real_cp\" \"\$@\"
"
chmod +x -- "$hidden_shim/cp"
set +e
PATH="$hidden_shim:$PATH" MUSIC_INGEST_STAGING="$hidden_staging" MUSIC_INGEST_MASTER="$hidden_master" MUSIC_INGEST_INFLIGHT="$hidden_inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$hidden_root/first.stdout" 2>"$hidden_root/first.stderr"
hidden_first_rc=$?
set -e
check 'hidden-root interruption fails while retaining claim' test "$hidden_first_rc" -eq 1
check 'hidden-root claim remains after interrupted copy' test -f "$hidden_inflight/Interrupted/file.flac"
check 'hidden-root source below supplied root publishes' test -f "$hidden_master/Fresh/file.flac"
check 'hidden descendant remains ignored' test -f "$hidden_staging/.hidden-child/ignored.flac"
rm -f -- "$hidden_shim/cp"
set +e
MUSIC_INGEST_STAGING="$hidden_staging" MUSIC_INGEST_MASTER="$hidden_master" MUSIC_INGEST_INFLIGHT="$hidden_inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$hidden_root/recovery.stdout" 2>"$hidden_root/recovery.stderr"
hidden_recovery_rc=$?
set -e
check 'hidden-root recovery succeeds' test "$hidden_recovery_rc" -eq 0
check 'hidden-root recovered claim publishes' content_equals "$hidden_master/Interrupted/file.flac" hidden-inflight-claim
check 'hidden-root recovered claim is removed' test ! -e "$hidden_inflight/Interrupted/file.flac"

echo '=== SIGKILL leaves recoverable claim and stale temp ==='
write_file "$staging/Killed/file.flac" 'before-kill'; age "$staging/Killed/file.flac"
kill_shim="$root/kill-bin"
kill_signal="$root/kill-sync-ready"
kill_release="$root/kill-release"
real_sync="$(command -v sync)"
mkdir -p -- "$kill_shim"
write_file "$kill_shim/sync" "#!/bin/sh
for arg do :; done
case \"\$arg\" in
  \"$master/Killed/.music-ingest.\"*)
    : >\"$kill_signal\"
    while [ ! -e \"$kill_release\" ]; do sleep 0.01; done
    ;;
esac
exec \"$real_sync\" \"\$@\"
"
chmod +x -- "$kill_shim/sync"
PATH="$kill_shim:$PATH" MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$root/killed.stdout" 2>"$root/killed.stderr" &
kill_pid=$!
for _ in $(seq 1 300); do
  [ -e "$kill_signal" ] && break
  sleep 0.01
done
check 'SIGKILL synchronization reached copied temp' test -e "$kill_signal"
kill -KILL "$kill_pid" 2>/dev/null || true
: >"$kill_release"
set +e
wait "$kill_pid"
kill_rc=$?
set -e
check 'SIGKILL interrupts the running adapter' test "$kill_rc" -eq 137
check 'SIGKILL leaves owned claim' test -f "$inflight/Killed/file.flac"
check 'SIGKILL leaves ownership marker' test -f "$inflight/Killed/file.flac.owner"
check 'SIGKILL leaves master temp for recovery cleanup' has_stale_temp "$master/Killed"
# A new Syncthing version appears after the old inode was claimed. It is fresh
# and therefore remains in staging while the marked old claim is recovered.
write_file "$root/killed-replacement" 'after-kill'; mv -nT -- "$root/killed-replacement" "$staging/Killed/file.flac"
if run_ingest; then rc=0; else rc=$?; fi
check 'recovery with replacement source succeeds' test "$rc" -eq 0
check 'recovery publishes claimed pre-kill bytes' content_equals "$master/Killed/file.flac" before-kill
check 'recovery removes stale master temp' no_stale_temp "$master/Killed"
check 'recovery removes owned claim and marker' test ! -e "$inflight/Killed/file.flac" -a ! -e "$inflight/Killed/file.flac.owner"
check 'post-kill replacement remains for stability window' content_equals "$staging/Killed/file.flac" after-kill

echo '=== no-clobber destination race ==='
write_file "$staging/Race/file.flac" 'claimed'; age "$staging/Race/file.flac"
real_sync="$(command -v sync)"
race_shim="$root/race-bin"
race_signal="$root/race-sync-ready"
race_release="$root/race-release"
mkdir -p -- "$race_shim"
write_file "$race_shim/sync" "#!/bin/sh
for arg do :; done
case \"\$arg\" in
  \"$master/Race/.music-ingest.\"*)
    : >\"$race_signal\"
    while [ ! -e \"$race_release\" ]; do sleep 0.01; done
    ;;
esac
exec \"$real_sync\" \"\$@\"
"
chmod +x -- "$race_shim/sync"
# The destination race is deterministic through a subprocess wrapper around
# the real sync boundary. The wrapper pauses after the real copy is synced,
# before the adapter's no-clobber rename. The writer publishes its competing
# file with an atomic rename, then releases the adapter. The script has no
# test-only branch or synchronization hook.
race_writer() {
  for _ in $(seq 1 200); do
    if [ -e "$race_signal" ]; then
      write_file "$root/race-destination" 'other-writer'
      mv -n -- "$root/race-destination" "$master/Race/file.flac"
      : >"$race_release"
      return 0
    fi
    sleep 0.01
  done
  return 1
}
race_writer & race_pid=$!
set +e
PATH="$race_shim:$PATH" MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$root/race.stdout" 2>"$root/race.stderr"
rc=$?
set -e
wait "$race_pid"
check 'destination race does not overwrite concurrent canonical writer' content_equals "$master/Race/file.flac" other-writer
check 'destination race quarantines claimed bytes' test -f "$staging/.conflicts/Race/file.flac"
check 'destination race leaves no claim behind' test ! -e "$inflight/Race/file.flac"

echo '=== no-target-directory destination race ==='
write_file "$staging/DirectoryRace/file.flac" 'directory-race'; age "$staging/DirectoryRace/file.flac"
directory_shim="$root/directory-bin"
directory_signal="$root/directory-sync-ready"
directory_release="$root/directory-release"
mkdir -p -- "$directory_shim"
write_file "$directory_shim/sync" "#!/bin/sh
for arg do :; done
case \"\$arg\" in
  \"$master/DirectoryRace/.music-ingest.\"*)
    : >\"$directory_signal\"
    while [ ! -e \"$directory_release\" ]; do sleep 0.01; done
    ;;
esac
exec \"$real_sync\" \"\$@\"
"
chmod +x -- "$directory_shim/sync"
directory_writer() {
  for _ in $(seq 1 300); do
    if [ -e "$directory_signal" ]; then
      mkdir -p -- "$master/DirectoryRace/file.flac"
      : >"$directory_release"
      return 0
    fi
    sleep 0.01
  done
  return 1
}
directory_writer & directory_pid=$!
set +e
PATH="$directory_shim:$PATH" MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$inflight" MUSIC_INGEST_STABILITY_SECONDS=60 bash "$script" >"$root/directory.stdout" 2>"$root/directory.stderr"
rc=$?
set -e
wait "$directory_pid"
check 'directory destination race returns conflict status' test "$rc" -eq 3
check 'directory destination remains a directory' test -d "$master/DirectoryRace/file.flac"
check 'directory destination does not swallow temp' no_stale_temp_anywhere "$master/DirectoryRace/file.flac"
check 'directory destination quarantines claim' test -f "$staging/.conflicts/DirectoryRace/file.flac"
check 'directory destination race leaves no claim' test ! -e "$inflight/DirectoryRace/file.flac"

echo '=== traversal errors fail closed ==='
if [ "$(id -u)" -ne 0 ]; then
  write_file "$staging/Unreadable/file.flac" 'unreadable'; age "$staging/Unreadable/file.flac"
  write_file "$staging/UnreadablePeer/file.flac" 'peer'; age "$staging/UnreadablePeer/file.flac"
  chmod 000 -- "$staging/Unreadable"
  if run_ingest; then rc=0; else rc=$?; fi
  chmod 700 -- "$staging/Unreadable"
  check 'unreadable staging subtree fails the run' test "$rc" -eq 1
  check 'eligible peer remains untouched after traversal failure' test -f "$staging/UnreadablePeer/file.flac"
  rm -rf -- "$staging/Unreadable" "$staging/UnreadablePeer"
else
  echo '  - traversal error fixture skipped when running as root'
fi

echo '=== serialized invocations ==='
write_file "$staging/Serial/file.flac" 'serial'; age "$staging/Serial/file.flac"
exec 8>"$inflight/.music-ingest.lock"
flock -x 8
set +e
MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$inflight" bash "$script" >"$root/serialized.stdout" 2>"$root/serialized.stderr" &
serial_pid=$!
set -e
sleep 0.1
check 'second invocation waits on adapter lock' test -f "$staging/Serial/file.flac"
flock -u 8
exec 8>&-
wait "$serial_pid"
check 'serialized invocation eventually publishes' test -f "$master/Serial/file.flac"

echo '=== cross-device claim guard (when /dev/shm differs) ==='
if [ "$(stat -c %d -- "$staging")" != "$(stat -c %d -- /dev/shm)" ]; then
  cross_inflight="/dev/shm/music-ingest-runtime-cross-$$"
  mkdir -p -- "$cross_inflight"
  write_file "$staging/Cross/file.flac" 'cross'; age "$staging/Cross/file.flac"
  set +e
  MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$cross_inflight" bash "$script" >"$root/cross.stdout" 2>"$root/cross.stderr"
  cross_rc=$?
  set -e
  check 'cross-device inflight fails before moving data' test "$cross_rc" -eq 1
  check 'cross-device guard retains staging source' test -f "$staging/Cross/file.flac"
  rmdir -- "$cross_inflight"
else
  echo '  - cross-device fixture skipped: /dev/shm shares staging device'
fi

echo '=== path-overlap guard ==='
write_file "$staging/Nested/file.flac" 'nested-path'; age "$staging/Nested/file.flac"
set +e
MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$staging/.inflight" bash "$script" >"$root/nested.stdout" 2>"$root/nested.stderr"
nested_rc=$?
set -e
check 'inflight nested in staging is rejected before moving data' test "$nested_rc" -eq 1
check 'overlap guard retains source' test -f "$staging/Nested/file.flac"

ln -s -- "$staging" "$root/inflight-alias"
set +e
MUSIC_INGEST_STAGING="$staging" MUSIC_INGEST_MASTER="$master" MUSIC_INGEST_INFLIGHT="$root/inflight-alias" bash "$script" >"$root/alias.stdout" 2>"$root/alias.stderr"
alias_rc=$?
set -e
check 'symlink alias overlap is rejected after normalization' test "$alias_rc" -eq 1
check 'alias overlap retains source' test -f "$staging/Nested/file.flac"
rm -rf -- "$staging/Nested"

escape_root="/tmp/music-ingest-runtime-escape-$$"
mkdir -p -- "$escape_root"
write_file "$escape_root/file.flac" 'outside-parent-sentinel'
ln -s -- "$escape_root" "$master/Escape"
write_file "$staging/Escape/file.flac" 'escaped-destination'; age "$staging/Escape/file.flac"
set +e
if run_ingest; then escape_rc=0; else escape_rc=$?; fi
set -e
check 'destination parent symlink escaping master fails closed' test "$escape_rc" -eq 1
check 'escaped destination claim remains recoverable' test -f "$inflight/Escape/file.flac"
check 'escaped destination receives no bytes' no_stale_temp_anywhere "$escape_root"
check 'existing escaped destination remains untouched' content_equals "$escape_root/file.flac" outside-parent-sentinel
rm -f -- "$master/Escape"
rm -rf -- "$escape_root"
if run_ingest; then rc=0; else rc=$?; fi
check 'escaped destination claim recovers after symlink removal' test "$rc" -eq 0
rm -rf -- "$master/Escape"

symlink_target="/tmp/music-ingest-runtime-target-$$"
mkdir -p -- "$symlink_target" "$master/SymlinkDest"
write_file "$symlink_target/file.flac" 'outside-sentinel'
ln -s -- "$symlink_target/file.flac" "$master/SymlinkDest/file.flac"
write_file "$staging/SymlinkDest/file.flac" 'inside-source'; age "$staging/SymlinkDest/file.flac"
if run_ingest; then symlink_destination_rc=0; else symlink_destination_rc=$?; fi
check 'existing destination symlink fails closed' test "$symlink_destination_rc" -eq 1
check 'existing destination symlink target remains untouched' content_equals "$symlink_target/file.flac" outside-sentinel
check 'existing destination symlink retains claim' test -f "$inflight/SymlinkDest/file.flac"
rm -f -- "$master/SymlinkDest/file.flac"
rm -rf -- "$symlink_target"
if run_ingest; then rc=0; else rc=$?; fi
check 'claim recovers after destination symlink removal' test "$rc" -eq 0
check 'recovered symlink destination publishes source' content_equals "$master/SymlinkDest/file.flac" inside-source

claim_symlink_target="/tmp/music-ingest-runtime-claim-target-$$"
mkdir -p -- "$claim_symlink_target" "$inflight/SymlinkClaim"
write_file "$claim_symlink_target/file.flac" 'claim-outside-sentinel'
ln -s -- "$claim_symlink_target/file.flac" "$inflight/SymlinkClaim/file.flac"
write_file "$staging/SymlinkClaim/file.flac" 'claim-inside-source'; age "$staging/SymlinkClaim/file.flac"
if run_ingest; then symlink_claim_rc=0; else symlink_claim_rc=$?; fi
check 'existing claim symlink fails closed' test "$symlink_claim_rc" -eq 1
check 'existing claim symlink target remains untouched' content_equals "$claim_symlink_target/file.flac" claim-outside-sentinel
check 'existing claim symlink retains staging source' test -f "$staging/SymlinkClaim/file.flac"
rm -f -- "$inflight/SymlinkClaim/file.flac"
rm -rf -- "$claim_symlink_target"
if run_ingest; then rc=0; else rc=$?; fi
check 'claim symlink path recovers after removal' test "$rc" -eq 0
check 'recovered claim symlink path publishes source' content_equals "$master/SymlinkClaim/file.flac" claim-inside-source

echo
echo "=== RESULT: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
