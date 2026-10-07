#!/usr/bin/env bash
#
# Semantic tests for pressure-cli.bash — no Nix, no real filesystem probing,
# no root. The CLI is assembled exactly as pressure.nix assembles it (policy
# as NORI_PRESSURE_* environment from the option values) but with the two
# documented test seams pointed at fixtures, so every classification,
# rejection and maintenance path is exercised against controlled bytes.
#
# Run:  bash src/infra/common/nixos/storage/pressure.test.sh
#
# Covered, in order:
#   * classification boundary the spec names: plentiful free data (77%),
#     near-full metadata (99%), 1 MiB unallocated → critical
#   * adequate expansion workspace at the same metadata level → not critical
#   * metadata warning band, and metadata below the critical threshold
#   * ordinary-space threshold carried onto a btrfs filesystem
#   * non-btrfs: null btrfs fields, ordinary-only semantics, no btrfs call
#   * read error / missing field / inconsistent numbers → exit 1, never healthy
#   * with-lock: held across the command, busy → 75, group+mode of the lock
#   * maintain: exact bounded data-only invocations, headroom short-circuit,
#     exhausted-workspace refusal, exclusive-operation defer, lock defer,
#     one maintenance per physical filesystem, and no argv that would widen it
set -uo pipefail

# The assembled CLI calls `jq` from PATH (the package wrapper pins jq through
# runtimeInputs; here we resolve one so the test runs without a dev shell).
jq_bin="${NORI_TEST_JQ:-}"
if [ -z "$jq_bin" ]; then
  candidate=$(command -v jq 2>/dev/null || true)
  case "$candidate" in
    /*) jq_bin=$candidate ;;
  esac
fi
if [ -z "$jq_bin" ]; then
  jq_bin=$(printf '%s\n' /nix/store/*-jq-*-bin/bin/jq 2>/dev/null | sort | tail -n 1)
fi
if [ -z "$jq_bin" ]; then
  echo "pressure.test.sh: jq is required (set NORI_TEST_JQ)" >&2
  exit 1
fi
PATH="$(dirname -- "$jq_bin"):$PATH"
export PATH

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

fixture="$work/fixture"
stub="$work/stub"
sysfs="$work/sysfs"
mkdir -p "$fixture" "$stub" "$sysfs" "$work/lock"
export BTRFS_FIXTURE_DIR="$fixture"
export STAT_FIXTURE_DIR="$fixture"
export BTRFS_STUB_LOG="$work/btrfs.log"
export BTRFS_FIXTURE_UUID="c87e6351-3b15-43fc-b276-45494258dd50"

cat >"$stub/stat" <<'STUB_STAT'
#!/usr/bin/env bash
set -u
last=''
for last in "$@"; do :; done
if [ -e "$STAT_FIXTURE_DIR/fail" ]; then
  echo "stat: cannot read filesystem information for $*" >&2
  exit 1
fi
if [ -e "$STAT_FIXTURE_DIR/fail-paths" ] && grep -qx -- "$last" "$STAT_FIXTURE_DIR/fail-paths"; then
  echo "stat: cannot read filesystem information for $last" >&2
  exit 1
fi
case "$*" in
  *%T*) cat "$STAT_FIXTURE_DIR/type" ;;
  *%b*) cat "$STAT_FIXTURE_DIR/blocks" ;;
  *%d*) cat "$STAT_FIXTURE_DIR/dev" ;;
  *)
    echo "stat stub: unexpected arguments: $*" >&2
    exit 2
    ;;
esac
STUB_STAT

cat >"$stub/btrfs" <<'STUB_BTRFS'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$BTRFS_STUB_LOG"
case "$1 $2" in
  "filesystem show")
    printf "Label: 'fixture'  uuid: %s\n" "$BTRFS_FIXTURE_UUID"
    ;;
  "filesystem usage")
    if [ -e "$BTRFS_FIXTURE_DIR/fail-usage" ]; then
      echo "ERROR: cannot read chunk info" >&2
      exit 1
    fi
    cat "$BTRFS_FIXTURE_DIR/usage"
    ;;
  "balance start")
    if [ -e "$BTRFS_FIXTURE_DIR/balance-fail" ]; then
      echo "ERROR: balance failed" >&2
      exit 1
    fi
    count=$(cat "$BTRFS_FIXTURE_DIR/balance-count" 2>/dev/null || echo 0)
    count=$((count + 1))
    printf '%s' "$count" >"$BTRFS_FIXTURE_DIR/balance-count"
    if [ -e "$BTRFS_FIXTURE_DIR/usage-stage-$count" ]; then
      cp "$BTRFS_FIXTURE_DIR/usage-stage-$count" "$BTRFS_FIXTURE_DIR/usage"
    fi
    echo "Done, had to relocate 0 out of 0 chunks"
    ;;
  *)
    echo "btrfs stub: unexpected invocation: $1 $2" >&2
    exit 2
    ;;
esac
STUB_BTRFS
chmod +x "$stub/stat" "$stub/btrfs"

cli="$work/nori-storage-pressure"
{
  echo '#!/usr/bin/env bash'
  cat <<ASSEMBLY
set -euo pipefail
export NORI_PRESSURE_METADATA_WARNING_PCT=85
export NORI_PRESSURE_METADATA_CRITICAL_PCT=95
export NORI_PRESSURE_WARNING_WORKSPACE_BYTES=21474836480
export NORI_PRESSURE_CRITICAL_WORKSPACE_BYTES=2147483648
export NORI_PRESSURE_ORDINARY_CRITICAL_PCT=95
export NORI_PRESSURE_LOCK_DIR='$work/lock'
export NORI_PRESSURE_LOCK_GROUP='$(id -gn)'
export NORI_PRESSURE_MAINTENANCE_USAGE=10
export NORI_PRESSURE_MAINTENANCE_LIMIT=4
export NORI_PRESSURE_HEADROOM_TARGET_BYTES=34359738368
export NORI_PRESSURE_STAT='$stub/stat'
export NORI_PRESSURE_BTRFS='$stub/btrfs'
export NORI_PRESSURE_SYSFS_BTRFS='$sysfs'
ASSEMBLY
  cat "$here/pressure-cli.bash"
} >"$cli"
chmod +x "$cli"

# ── alarm harness ───────────────────────────────────────────────────────
# The alarm body (pressure-alarm.bash) is assembled the same way disk-alert
# runs it: environment contract + body + `main <mountpoints>`. The alert sink
# is a recording double (an external system we must not actually call), and
# ALERT_FAIL=1 simulates a delivery failure.
alert_log="$work/alerts.log"
: >"$alert_log"
cat >"$stub/nori-alert" <<'STUB_ALERT'
#!/usr/bin/env bash
printf 'ALERT\n' >>"$ALERT_LOG"
for arg in "$@"; do printf 'A|%s\n' "$arg" >>"$ALERT_LOG"; done
[ "${ALERT_FAIL:-0}" = 1 ] && exit 1
exit 0
STUB_ALERT
chmod +x "$stub/nori-alert"

state_dir="$work/state"
mkdir -p "$state_dir"
alarm="$work/nori-disk-alert"
{
  echo '#!/usr/bin/env bash'
  cat <<ALARM_ASSEMBLY
set -euo pipefail
export ALERT_LOG='$alert_log'
export PRESSURE_CLI='$cli'
export PRESSURE_ALERT_CMD='$stub/nori-alert'
export PRESSURE_HOST='fixture-host'
export PRESSURE_STATE_DIR='$state_dir'
export PRESSURE_META_WARN_PCT=85
export PRESSURE_META_CRIT_PCT=95
export PRESSURE_WARN_WORKSPACE_BYTES=21474836480
export PRESSURE_CRIT_WORKSPACE_BYTES=2147483648
ALARM_ASSEMBLY
  cat "$here/pressure-alarm.bash"
  echo 'main "$@"'
} >"$alarm"
chmod +x "$alarm"

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  printf 'ok   %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1"
}
assert_eq() { # DESC WANT GOT
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$2' got '$3')"; fi
}
assert_contains() { # DESC NEEDLE HAYSTACK
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) bad "$1 (missing '$2' in: $3)" ;;
  esac
}
assert_grep() { # DESC PATTERN FILE
  if grep -q -- "$2" "$3"; then ok "$1"; else bad "$1 (missing '$2' in $3)"; fi
}
assert_grep_exact() { # DESC LINE FILE
  if grep -qx -- "$2" "$3"; then ok "$1"; else bad "$1 (missing line '$2' in $3)"; fi
}
assert_nogrep() { # DESC PATTERN FILE
  if grep -q -- "$2" "$3"; then bad "$1 (unexpected '$2' in $3)"; else ok "$1"; fi
}
assert_absent_file() { # DESC FILE
  if [ -e "$2" ]; then bad "$1 (unexpected file $2)"; else ok "$1"; fi
}

target="$work/target"
: >"$target"

# Barrier: after killing a lock holder, wait until the lock is actually free so
# no later case inherits a held lock from a slow-to-die process.
wait_lock_free() {
  for _ in $(seq 1 100); do
    "$cli" with-lock "$target" true 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

set_fs() { # TYPE BLOCKS BFREE BAVAIL DEV
  printf '%s\n' "$1" >"$fixture/type"
  printf '%s %s %s\n' "$2" "$3" "$4" >"$fixture/blocks"
  printf '%s\n' "$5" >"$fixture/dev"
}

# A realistic `btrfs filesystem usage --raw` block, with the Overall section
# carrying device geometry and one Metadata block-group line. Numbers are raw
# bytes because the CLI parses exactly this shape.
set_usage() { # SIZE ALLOC UNALLOC META_SIZE META_USED [MISSING_DEVICES]
  cat >"$fixture/usage" <<USAGE_FIXTURE
Overall:
    Device size:              $1
    Device allocated:         $2
    Device unallocated:       $3
    Device missing:           ${6:-0}
    Device slack:             0
    Used:                     0
    Data ratio:               1.00
    Metadata ratio:           2.00
    Global reserve:           536870912
    Multiple profiles:        no

Data,single: Size:853624750080, Used:648013291520 (75.91%)

Metadata,DUP: Size:$4, Used:$5 (96.37%)

System,DUP: Size:8388608, Used:131072 (1.56%)
USAGE_FIXTURE
  rm -f "$fixture/balance-count" "$fixture"/usage-stage-*
  # A fixture filesystem starts free: the kernel marker must be readable and
  # say "none" before maintenance may run.
  mkdir -p "$sysfs/$BTRFS_FIXTURE_UUID"
  printf 'none' >"$sysfs/$BTRFS_FIXTURE_UUID/exclusive_operation"
}

reset_fixture() {
  rm -f "$fixture/fail" "$fixture/fail-paths" "$fixture/fail-usage" "$fixture/balance-fail" \
    "$fixture/balance-count" "$fixture"/usage-stage-*
  : >"$BTRFS_STUB_LOG"
}

DEVICE_SIZE=100000000000
META_TOTAL=100000000000
META_USED_99PCT=99090000000

# ── the boundary the spec names ─────────────────────────────────────────
# Plentiful free data (77% ordinary), near-full metadata (99%), and no
# expansion workspace (1 MiB unallocated): critical.
reset_fixture
set_fs btrfs 243928064 56909956 55956236 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$META_USED_99PCT"
json=$("$cli" probe "$target")
rc=$?
assert_eq "boundary: probe exits 0" 0 "$rc"
assert_eq "boundary: state critical" critical "$(printf '%s' "$json" | jq -r .state)"
assert_eq "boundary: ordinary 77%" 77 "$(printf '%s' "$json" | jq -r .ordinary_used_pct)"
assert_eq "boundary: metadata 99%" 99 "$(printf '%s' "$json" | jq -r .metadata_used_pct)"
assert_eq "boundary: metadata used bytes" "$META_USED_99PCT" "$(printf '%s' "$json" | jq -r .metadata_used_bytes)"
assert_eq "boundary: unallocated bytes" 1048576 "$(printf '%s' "$json" | jq -r .unallocated_bytes)"
assert_eq "boundary: fs_uuid" "$BTRFS_FIXTURE_UUID" "$(printf '%s' "$json" | jq -r .fs_uuid)"
assert_eq "boundary: json keys" \
  "fs_type,fs_uuid,metadata_total_bytes,metadata_used_bytes,metadata_used_pct,ordinary_used_pct,path,state,unallocated_bytes" \
  "$(printf '%s' "$json" | jq -r 'keys | join(",")')"
"$cli" check "$target" >/dev/null 2>&1
assert_eq "boundary: check exits 75" 75 "$?"

# Same metadata, adequate expansion workspace (32 GiB) → not critical.
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 34359738368))" 34359738368 "$META_TOTAL" "$META_USED_99PCT"
state=$("$cli" probe "$target" | jq -r .state)
assert_eq "adequate workspace: state healthy (not critical/warning)" healthy "$state"
"$cli" check "$target" >/dev/null 2>&1
assert_eq "adequate workspace: check exits 0" 0 "$?"

# Metadata in the warning band with scarce workspace → warning, not critical.
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 5368709120))" 5368709120 "$META_TOTAL" "$META_USED_99PCT"
assert_eq "warning band: 99% metadata + 5 GiB workspace warns" warning "$("$cli" probe "$target" | jq -r .state)"
"$cli" check "$target" >/dev/null 2>&1
assert_eq "warning band: check exits 0" 0 "$?"

# Metadata below the critical threshold is never critical, even with no
# expansion workspace (this is what keeps high-but-expandable from paging).
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" 90000000000
assert_eq "below critical metadata: warns, not critical" warning "$("$cli" probe "$target" | jq -r .state)"

# Metadata well below the warning threshold, ample workspace → healthy.
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 34359738368))" 34359738368 "$META_TOTAL" 50000000000
assert_eq "low metadata: healthy" healthy "$("$cli" probe "$target" | jq -r .state)"

# Ordinary-space threshold is carried onto btrfs (99% used → critical even
# with a healthy metadata reading and ample workspace).
reset_fixture
set_fs btrfs 1000 30 10 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 34359738368))" 34359738368 "$META_TOTAL" 50000000000
assert_eq "ordinary critical on btrfs: critical" critical "$("$cli" probe "$target" | jq -r .state)"
"$cli" check "$target" >/dev/null 2>&1
assert_eq "ordinary critical on btrfs: check exits 75" 75 "$?"

# Non-btrfs: btrfs fields null, ordinary semantics only, and the btrfs binary
# is never invoked.
reset_fixture
set_fs ext4 1000 800 190 2065
json=$("$cli" probe "$target")
assert_eq "non-btrfs: fs_type" ext4 "$(printf '%s' "$json" | jq -r .fs_type)"
assert_eq "non-btrfs: fs_uuid null" null "$(printf '%s' "$json" | jq -r .fs_uuid)"
assert_eq "non-btrfs: metadata_used_bytes null" null "$(printf '%s' "$json" | jq -r .metadata_used_bytes)"
assert_eq "non-btrfs: metadata_total_bytes null" null "$(printf '%s' "$json" | jq -r .metadata_total_bytes)"
assert_eq "non-btrfs: metadata_used_pct null" null "$(printf '%s' "$json" | jq -r .metadata_used_pct)"
assert_eq "non-btrfs: unallocated_bytes null" null "$(printf '%s' "$json" | jq -r .unallocated_bytes)"
assert_eq "non-btrfs: healthy at 52%" healthy "$(printf '%s' "$json" | jq -r .state)"
assert_eq "non-btrfs: no btrfs invocation" "" "$(cat "$BTRFS_STUB_LOG")"
"$cli" check "$target" >/dev/null 2>&1
assert_eq "non-btrfs: check exits 0" 0 "$?"

# Non-btrfs keeps the ordinary critical alarm.
reset_fixture
set_fs ext4 1000 30 10 2065
assert_eq "non-btrfs ordinary critical: critical" critical "$("$cli" probe "$target" | jq -r .state)"
"$cli" check "$target" >/dev/null 2>&1
assert_eq "non-btrfs ordinary critical: check exits 75" 75 "$?"

# ── errors are errors, never healthy ────────────────────────────────────
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$META_USED_99PCT"
: >"$fixture/fail"
out=$("$cli" check "$target" 2>"$work/err")
rc=$?
assert_eq "read error: check exits 1" 1 "$rc"
assert_eq "read error: nothing on stdout" "" "$out"
if [ -s "$work/err" ]; then ok "read error: stderr not empty"; else bad "read error: stderr not empty"; fi
rm -f "$fixture/fail"

# Missing Device unallocated field.
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$META_USED_99PCT"
grep -v 'Device unallocated' "$fixture/usage" >"$fixture/usage.trimmed"
mv "$fixture/usage.trimmed" "$fixture/usage"
"$cli" check "$target" >/dev/null 2>"$work/err"
assert_eq "missing field: check exits 1" 1 "$?"
assert_contains "missing field: names the field" "Device unallocated" "$(cat "$work/err")"

# Self-inconsistent device geometry.
reset_fixture
set_usage "$DEVICE_SIZE" 100 "$((DEVICE_SIZE - 1048576))" "$META_TOTAL" "$META_USED_99PCT"
"$cli" check "$target" >/dev/null 2>"$work/err"
assert_eq "inconsistent geometry: check exits 1" 1 "$?"
assert_contains "inconsistent geometry: diagnostic" "inconsistent measurement" "$(cat "$work/err")"

# A degraded filesystem (a device missing from the device set) can report
# unallocated space for hardware that is not present: fail closed.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" 50000000000 536870912
"$cli" check "$target" >/dev/null 2>"$work/err"
assert_eq "degraded filesystem: check exits 1" 1 "$?"
assert_contains "degraded filesystem: reported as degraded" "is degraded" "$(cat "$work/err")"
assert_contains "degraded filesystem: reports the missing byte count" "536870912" "$(cat "$work/err")"

# A missing Device-missing field cannot be assumed to mean zero.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" 50000000000
grep -v 'Device missing' "$fixture/usage" >"$fixture/usage.trimmed"
mv "$fixture/usage.trimmed" "$fixture/usage"
"$cli" check "$target" >/dev/null 2>"$work/err"
assert_eq "missing Device missing field: check exits 1" 1 "$?"
assert_contains "missing Device missing field: names the field" "Device missing" "$(cat "$work/err")"

# Metadata used above metadata size.
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$((META_TOTAL + 1))"
"$cli" check "$target" >/dev/null 2>"$work/err"
assert_eq "inconsistent metadata: check exits 1" 1 "$?"
assert_contains "inconsistent metadata: diagnostic" "metadata used" "$(cat "$work/err")"

# btrfs usage command failure.
reset_fixture
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$META_USED_99PCT"
: >"$fixture/fail-usage"
"$cli" check "$target" >/dev/null 2>"$work/err"
assert_eq "usage failure: check exits 1" 1 "$?"
rm -f "$fixture/fail-usage"

# ── locking ─────────────────────────────────────────────────────────────
reset_fixture
set_fs btrfs 1000 800 190 34
out=$("$cli" with-lock "$target" printf 'inside-lock')
assert_eq "with-lock: command output preserved" inside-lock "$out"
assert_eq "with-lock: succeeds when free" 0 "$?"

lockfile="$work/lock/uuid-$BTRFS_FIXTURE_UUID.lock"
assert_eq "with-lock: lock file per filesystem UUID" "$lockfile" "$(ls "$work/lock"/*.lock)"
assert_eq "with-lock: lock file mode" 660 "$(stat -c %a "$lockfile")"
assert_eq "with-lock: lock file group" "$(id -gn)" "$(stat -c %G "$lockfile")"

"$cli" with-lock "$target" sleep 3 &
holder=$!
busy_rc=1
for _ in $(seq 1 30); do
  "$cli" with-lock "$target" true 2>"$work/err" && busy_rc=0 || busy_rc=$?
  [ "$busy_rc" = 75 ] && break
  sleep 0.1
done
assert_eq "with-lock: second holder refused with 75" 75 "$busy_rc"
assert_contains "with-lock: refusal is explicit" "lock busy" "$(cat "$work/err")"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
wait_lock_free || bad "lock holder did not release its lock"

# Non-btrfs paths lock by device number, not by mountpoint.
reset_fixture
set_fs ext4 1000 800 190 2065
"$cli" with-lock "$target" true
assert_eq "with-lock: non-btrfs lock by device" 0 "$?"
assert_eq "with-lock: non-btrfs lock file" "$work/lock/dev-2065.lock" "$(ls "$work/lock"/dev-*.lock)"
rm -f "$work/lock"/dev-*.lock

# ── bounded maintenance ─────────────────────────────────────────────────
maintenance_log() { grep '^balance start' "$BTRFS_STUB_LOG" || true; }

# Headroom below target and workspace left → both passes, exact argv.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1073741824))" 1073741824 "$META_TOTAL" "$META_USED_99PCT"
# The reclaim pass frees some room (8 GiB, still under the 32 GiB target),
# then the compaction pass frees more.
cat >"$fixture/usage-stage-1" <<POST
Overall:
    Device size:              $DEVICE_SIZE
    Device allocated:         $((DEVICE_SIZE - 8589934592))
    Device unallocated:       8589934592
    Device missing:           0

Metadata,DUP: Size:$META_TOTAL, Used:80000000000 (80.00%)
POST
cat >"$fixture/usage-stage-2" <<POST
Overall:
    Device size:              $DEVICE_SIZE
    Device allocated:         $((DEVICE_SIZE - 42949672960))
    Device unallocated:       42949672960
    Device missing:           0

Metadata,DUP: Size:$META_TOTAL, Used:60000000000 (60.00%)
POST
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: exits 0" 0 "$?"
assert_eq "maintain: exactly the two bounded data passes" \
  "balance start -dusage=0,limit=4 -- $target
balance start -dusage=10,limit=4 -- $target" \
  "$(maintenance_log)"
assert_contains "maintain: reports the reclaimed bytes" "unallocated 8589934592 -> 42949672960" "$(cat "$work/err")"

# Headroom already above target → only the empty block-group pass runs.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" "$META_USED_99PCT"
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: headroom short-circuit exits 0" 0 "$?"
assert_eq "maintain: only the reclaim pass" "balance start -dusage=0,limit=4 -- $target" "$(maintenance_log)"

# Workspace exhausted after the reclaim pass → actionable refusal, no
# compaction, and no deletion of anything.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$META_USED_99PCT"
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: exhausted workspace exits 1" 1 "$?"
assert_eq "maintain: refuses compaction" "balance start -dusage=0,limit=4 -- $target" "$(maintenance_log)"
assert_contains "maintain: refusal is actionable" "refusing further compaction" "$(cat "$work/err")"

# Another exclusive filesystem operation owns the filesystem → defer.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" "$META_USED_99PCT"
printf 'balance' >"$sysfs/$BTRFS_FIXTURE_UUID/exclusive_operation"
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: defers to exclusive operation" 0 "$?"
assert_eq "maintain: no balance while another operation owns it" "" "$(maintenance_log)"
assert_contains "maintain: deferral names the operation" 'exclusive filesystem operation "balance"' "$(cat "$work/err")"

# The kernel marker is authoritative: a missing or unreadable marker means the
# owner is unknown, which is an actionable error — never an implicit "free".
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" "$META_USED_99PCT"
rm -f "$sysfs/$BTRFS_FIXTURE_UUID/exclusive_operation"
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: missing exclusive-operation marker exits 1" 1 "$?"
assert_eq "maintain: no balance when the owner is unknown" "" "$(maintenance_log)"
assert_contains "maintain: missing marker is actionable" "refusing allocation maintenance" "$(cat "$work/err")"

reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" "$META_USED_99PCT"
: >"$sysfs/$BTRFS_FIXTURE_UUID/exclusive_operation"
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: empty exclusive-operation marker exits 1" 1 "$?"
assert_eq "maintain: no balance on an empty marker" "" "$(maintenance_log)"
assert_contains "maintain: empty marker is actionable" "empty exclusive-operation marker" "$(cat "$work/err")"

# The snapshot writer holds the lock → defer, do not race it.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1073741824))" 1073741824 "$META_TOTAL" "$META_USED_99PCT"
rm -f "$work/lock-held"
"$cli" with-lock "$target" bash -c "touch '$work/lock-held'; sleep 3" &
holder=$!
for _ in $(seq 1 100); do
  [ -e "$work/lock-held" ] && break
  sleep 0.1
done
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: defers while the lock is held" 0 "$?"
assert_eq "maintain: no balance under a held lock" "" "$(maintenance_log)"
assert_contains "maintain: lock deferral is explicit" "another holder owns" "$(cat "$work/err")"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
wait_lock_free || bad "lock holder did not release its lock"

# A path whose measurement dies is reported and skipped; the remaining
# filesystems are still maintained, and the run still fails.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" "$META_USED_99PCT"
printf '%s\n' "$work/broken-target" >"$fixture/fail-paths"
"$cli" maintain "$work/broken-target" "$target" 2>"$work/err"
assert_eq "maintain aggregation: run fails" 1 "$?"
assert_eq "maintain aggregation: later filesystem still maintained" \
  "balance start -dusage=0,limit=4 -- $target" "$(maintenance_log)"
assert_contains "maintain aggregation: skip is logged" "skipping it" "$(cat "$work/err")"

# Two paths on one physical filesystem are maintained once.
reset_fixture
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 68719476736))" 68719476736 "$META_TOTAL" "$META_USED_99PCT"
"$cli" maintain "$target" "$work/target2" 2>"$work/err"
assert_eq "maintain: dedup exits 0" 0 "$?"
assert_eq "maintain: one reclaim for two paths on one filesystem" \
  "balance start -dusage=0,limit=4 -- $target" "$(maintenance_log)"
assert_contains "maintain: dedup is reported" "maintained once" "$(cat "$work/err")"

# Non-btrfs maintenance is a no-op, and the btrfs binary is never called.
reset_fixture
set_fs ext4 1000 800 190 2065
"$cli" maintain "$target" 2>"$work/err"
assert_eq "maintain: non-btrfs is a no-op" 0 "$?"
assert_eq "maintain: no btrfs invocation for non-btrfs" "" "$(cat "$BTRFS_STUB_LOG")"
assert_contains "maintain: non-btrfs is reported" "not btrfs" "$(cat "$work/err")"

# ── alarm: critical alert, once-per-episode warning, fail-closed ────────
alert_count() { grep -c '^ALERT$' "$alert_log" 2>/dev/null || true; }
stamp_path() { printf '%s/%s.warning' "$state_dir" "$BTRFS_FIXTURE_UUID"; }

reset_fixture
: >"$alert_log"
rm -rf "$state_dir"
mkdir -p "$state_dir"
set_fs btrfs 1000 800 190 34
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 5368709120))" 5368709120 100000000000 90000000000
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
rc=$?
assert_eq "alarm warning: exits 0" 0 "$rc"
assert_eq "alarm warning: exactly one alert" 1 "$(alert_count)"
assert_grep_exact "alarm warning: severity warning" 'A|warning' "$alert_log"
assert_grep "alarm warning: delivery is required" '--require-delivery' "$alert_log"
assert_grep "alarm warning: title names the mount" "disk pressure warning ($target " "$alert_log"
assert_grep "alarm warning: body carries metadata utilization" 'btrfs metadata 90%' "$alert_log"
assert_grep "alarm warning: body carries metadata bytes" '90000000000' "$alert_log"
assert_grep "alarm warning: body carries unallocated bytes" '5368709120' "$alert_log"
assert_grep "alarm warning: body carries the runbook" 'storage-full.md' "$alert_log"
assert_eq "alarm warning: stamp written after successful delivery" warning "$(cat "$(stamp_path)" 2>/dev/null)"

"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm warning repeat: no second alert" 1 "$(alert_count)"
assert_contains "alarm warning repeat: reported as already notified" "already notified" "$(cat "$work/alarm.err")"

# Recovery clears the stamp, so the next warning episode alerts again.
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 34359738368))" 34359738368 "$META_TOTAL" 50000000000
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm healthy: exits 0" 0 "$?"
assert_eq "alarm healthy: no alert" 1 "$(alert_count)"
assert_absent_file "alarm healthy: stamp cleared" "$(stamp_path)"

set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 5368709120))" 5368709120 100000000000 90000000000
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm re-arm: warning after recovery alerts again" 2 "$(alert_count)"

# Critical escalates, clears the warning stamp, and keeps urgent delivery.
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 1048576))" 1048576 "$META_TOTAL" "$META_USED_99PCT"
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm critical: exits 0" 0 "$?"
assert_eq "alarm critical: alert delivered" 3 "$(alert_count)"
assert_grep_exact "alarm critical: severity urgent" 'A|urgent' "$alert_log"
assert_grep "alarm critical: title names the mount" "disk critical ($target " "$alert_log"
assert_grep "alarm critical: body carries unallocated bytes" '1048576' "$alert_log"
assert_absent_file "alarm critical: stamp cleared" "$(stamp_path)"

# A warning whose delivery fails is NOT marked notified, and the next run
# retries it.
set_usage "$DEVICE_SIZE" "$((DEVICE_SIZE - 5368709120))" 5368709120 100000000000 90000000000
ALERT_FAIL=1 "$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm warning: failed delivery fails the run" 1 "$?"
assert_eq "alarm warning: failed delivery still attempted" 4 "$(alert_count)"
assert_absent_file "alarm warning: failed delivery is not marked notified" "$(stamp_path)"
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm warning: retried after failed delivery" 5 "$(alert_count)"
assert_eq "alarm warning: stamp written on the successful retry" warning "$(cat "$(stamp_path)" 2>/dev/null)"

# Non-btrfs critical keeps the ordinary alarm and carries no btrfs bytes.
: >"$alert_log"
set_fs ext4 1000 30 10 2065
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm non-btrfs critical: exits 0" 0 "$?"
assert_eq "alarm non-btrfs critical: alert delivered" 1 "$(alert_count)"
assert_grep_exact "alarm non-btrfs critical: severity urgent" 'A|urgent' "$alert_log"
assert_nogrep "alarm non-btrfs critical: no btrfs fields" 'btrfs metadata' "$alert_log"

# A failed measurement alerts, fails the run, and is never silent.
: >"$alert_log"
set_fs btrfs 1000 800 190 34
: >"$fixture/fail"
"$alarm" "$target" >/dev/null 2>"$work/alarm.err"
assert_eq "alarm measurement error: fails the run" 1 "$?"
assert_grep "alarm measurement error: alert delivered" "disk measurement failed ($target)" "$alert_log"
assert_grep "alarm measurement error: body explains why" 'could not be measured' "$alert_log"
rm -f "$fixture/fail"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
