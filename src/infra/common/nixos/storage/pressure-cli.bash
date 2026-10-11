# shellcheck shell=bash
#
# nori-storage-pressure — the single measurement + classification construct
# for workstation filesystem allocation pressure. The alarm, the snapshot
# guard and bounded maintenance all read these numbers, so they cannot
# disagree about what "critical" means.
#
# This file is the implementation body of the package built in pressure.nix.
# The package wrapper supplies policy as NORI_PRESSURE_* environment
# variables (thresholds, lock location/group, maintenance budget) straight
# from the `nori.storagePressure` options; this script hardcodes no
# threshold. NORI_PRESSURE_STAT, NORI_PRESSURE_BTRFS and
# NORI_PRESSURE_SYSFS_BTRFS exist ONLY for tests that assemble this body
# directly (pressure.test.sh): the package wrapper unsets them, so nothing in
# a caller's environment can displace the pinned binaries or the kernel
# counter path.
#
# Subcommands:
#   probe PATH             measure + classify; prints JSON (state is in it)
#   check PATH             same JSON; 0 healthy|warning, 75 critical, 1 error
#   with-lock PATH CMD...  nonblocking filesystem-identity lock held across
#                          CMD; 75 when another owner holds the lock
#   maintain PATH...       bounded DATA-ONLY allocation maintenance
#                          1 real error (takes precedence), 75 workspace
#                          refusal, 0 otherwise (including owner/lock defer)
#
# Measurement errors are errors, never healthy: an unreadable path, a
# missing or malformed `btrfs filesystem usage` field, or self-inconsistent
# btrfs numbers all exit nonzero with a diagnostic on stderr.
#
# btrfs parsing is `LC_ALL=C ... --raw`: every number is a plain byte count,
# so the parse is exact integer arithmetic with no unit table to drift.

export LC_ALL=C

: "${NORI_PRESSURE_METADATA_WARNING_PCT:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_METADATA_CRITICAL_PCT:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_WARNING_WORKSPACE_BYTES:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_CRITICAL_WORKSPACE_BYTES:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_ORDINARY_CRITICAL_PCT:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_LOCK_DIR:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_LOCK_GROUP:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_MAINTENANCE_USAGE:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_MAINTENANCE_LIMIT:?must be set by the pressure package wrapper}"
: "${NORI_PRESSURE_HEADROOM_TARGET_BYTES:?must be set by the pressure package wrapper}"

STAT_BIN=${NORI_PRESSURE_STAT:-stat}
BTRFS_BIN=${NORI_PRESSURE_BTRFS:-btrfs}
SYSFS_BTRFS=${NORI_PRESSURE_SYSFS_BTRFS:-/sys/fs/btrfs}

# Measurement outputs, filled by measure(). Bytes and percentages stay raw
# integers (or the literal `null` for a non-btrfs filesystem) so the JSON is
# a faithful projection of what was measured.
m_type=
m_uuid=null
m_ordinary=
m_meta_used=null
m_meta_total=null
m_meta_pct=null
m_unalloc=null
state=

die() {
  printf 'nori-storage-pressure: %s\n' "$*" >&2
  exit 1
}

is_uint() {
  case ${1:-} in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

fs_type_of() { "$STAT_BIN" -f -c %T -- "$1" 2>/dev/null; }

fs_device_of() { "$STAT_BIN" -Lc %d -- "$1" 2>/dev/null; }

statfs_triple() { "$STAT_BIN" -f -c '%b %f %a' -- "$1" 2>/dev/null; }

btrfs_uuid() {
  local path=$1 out='' line='' uuid=''
  out=$("$BTRFS_BIN" filesystem show --raw -- "$path" 2>&1) ||
    die "btrfs filesystem show failed for $path: $out"
  while IFS= read -r line; do
    if [[ $line =~ uuid:[[:space:]]*([0-9a-fA-F][0-9a-fA-F-]+) ]]; then
      uuid=${BASH_REMATCH[1]}
      break
    fi
  done <<<"$out"
  [ -n "$uuid" ] || die "no filesystem uuid in 'btrfs filesystem show' output for $path"
  printf '%s' "$uuid"
}

# Parse `btrfs filesystem usage --raw` strictly. Only the Overall section
# supplies device geometry (per-device lines and the Unallocated section are
# deliberately not read: with several physical devices the Overall totals are
# already the filesystem-wide sums). Metadata block-group lines may be one
# per profile/type, so they are summed.
parse_btrfs_usage() {
  local path=$1 text=$2 line='' in_overall=0
  local dev_size='' dev_alloc='' dev_unalloc='' dev_missing=''
  local meta_size=0 meta_used=0 meta_lines=0
  while IFS= read -r line; do
    if [ "$line" = "Overall:" ]; then
      in_overall=1
      continue
    fi
    if [ "$in_overall" -eq 1 ]; then
      if [ -z "${line//[[:space:]]/}" ]; then
        in_overall=0
        continue
      fi
      if [[ $line =~ ^[[:space:]]*Device[[:space:]]+size:[[:space:]]*([0-9]+) ]]; then
        dev_size=${BASH_REMATCH[1]}
        continue
      fi
      if [[ $line =~ ^[[:space:]]*Device[[:space:]]+allocated:[[:space:]]*([0-9]+) ]]; then
        dev_alloc=${BASH_REMATCH[1]}
        continue
      fi
      if [[ $line =~ ^[[:space:]]*Device[[:space:]]+unallocated:[[:space:]]*([0-9]+) ]]; then
        dev_unalloc=${BASH_REMATCH[1]}
        continue
      fi
      if [[ $line =~ ^[[:space:]]*Device[[:space:]]+missing:[[:space:]]*([0-9]+) ]]; then
        dev_missing=${BASH_REMATCH[1]}
        continue
      fi
      continue
    fi
    if [[ $line =~ ^Metadata[^:]*:[[:space:]]*Size:[[:space:]]*([0-9]+),[[:space:]]*Used:[[:space:]]*([0-9]+) ]]; then
      meta_size=$((meta_size + BASH_REMATCH[1]))
      meta_used=$((meta_used + BASH_REMATCH[2]))
      meta_lines=$((meta_lines + 1))
    fi
  done <<<"$text"

  is_uint "$dev_size" || die "missing 'Device size' in 'btrfs filesystem usage' output for $path"
  is_uint "$dev_alloc" || die "missing 'Device allocated' in 'btrfs filesystem usage' output for $path"
  is_uint "$dev_unalloc" || die "missing 'Device unallocated' in 'btrfs filesystem usage' output for $path"
  # `Device missing` is the amount of device space in bytes that the
  # filesystem cannot reach (a device in the set is absent). A degraded
  # filesystem reports unallocated space for hardware that is not there, so
  # its numbers can look healthier than the surviving devices are: fail closed
  # instead of classifying a partial device set.
  is_uint "$dev_missing" || die "missing 'Device missing' in 'btrfs filesystem usage' output for $path"
  [ "$dev_missing" -eq 0 ] ||
    die "filesystem $path is degraded: $dev_missing bytes of device space are missing from the device set"
  [ "$dev_size" -gt 0 ] || die "zero device size for $path"
  [ $((dev_alloc + dev_unalloc)) -eq "$dev_size" ] ||
    die "inconsistent measurement for $path: allocated $dev_alloc + unallocated $dev_unalloc != device size $dev_size"
  [ "$meta_lines" -ge 1 ] || die "no Metadata block-group line in 'btrfs filesystem usage' output for $path"
  [ "$meta_size" -gt 0 ] || die "zero metadata size for $path"
  [ "$meta_used" -le "$meta_size" ] ||
    die "inconsistent measurement for $path: metadata used $meta_used > metadata size $meta_size"

  m_meta_total=$meta_size
  m_meta_used=$meta_used
  m_meta_pct=$((meta_used * 100 / meta_size))
  m_unalloc=$dev_unalloc
}

# measure PATH — sets m_* above; dies on any missing/inconsistent input.
measure() {
  local path=$1 type='' triple='' blocks='' bfree='' bavail='' denom='' usage=''
  type=$(fs_type_of "$path") || die "cannot read filesystem type of $path"
  [ -n "$type" ] || die "empty filesystem type for $path"
  triple=$(statfs_triple "$path") || die "cannot read statfs of $path"
  read -r blocks bfree bavail <<<"$triple"
  is_uint "$blocks" || die "malformed statfs for $path: '$triple'"
  is_uint "$bfree" || die "malformed statfs for $path: '$triple'"
  is_uint "$bavail" || die "malformed statfs for $path: '$triple'"
  denom=$(((blocks - bfree) + bavail))
  [ "$denom" -gt 0 ] || die "inconsistent statfs for $path: zero total capacity"

  m_type=$type
  # df's percentage, computed from the same statfs numbers: ceil of
  # used/(used+available), so the ordinary alarm keeps the threshold
  # semantics it had when it read `df --output=pcent`.
  m_ordinary=$((((blocks - bfree) * 100 + denom - 1) / denom))
  m_uuid=null
  m_meta_used=null
  m_meta_total=null
  m_meta_pct=null
  m_unalloc=null

  if [ "$type" = btrfs ]; then
    m_uuid=$(btrfs_uuid "$path") || exit 1
    usage=$("$BTRFS_BIN" filesystem usage --raw -- "$path" 2>&1) ||
      die "btrfs filesystem usage failed for $path: $usage"
    parse_btrfs_usage "$path" "$usage"
  fi
}

# classify — maps the measurement to healthy|warning|critical.
#
# critical: ordinary usage at its threshold (the pre-existing alarm), OR
#           metadata at/above the critical threshold AND unallocated device
#           space at/below the critical workspace — i.e. metadata pressure
#           with no room to expand.
# warning:  metadata at/above the warning threshold AND unallocated space
#           below the warning workspace. High metadata with adequate
#           expansion workspace is NOT critical.
# Non-btrfs filesystems keep the ordinary-space behaviour and never report
# metadata-derived states.
classify() {
  if [ "$m_type" = btrfs ]; then
    if [ "$m_ordinary" -ge "$NORI_PRESSURE_ORDINARY_CRITICAL_PCT" ] ||
      { [ "$m_meta_pct" -ge "$NORI_PRESSURE_METADATA_CRITICAL_PCT" ] &&
        [ "$m_unalloc" -le "$NORI_PRESSURE_CRITICAL_WORKSPACE_BYTES" ]; }; then
      state=critical
    elif [ "$m_meta_pct" -ge "$NORI_PRESSURE_METADATA_WARNING_PCT" ] &&
      [ "$m_unalloc" -lt "$NORI_PRESSURE_WARNING_WORKSPACE_BYTES" ]; then
      state=warning
    else
      state=healthy
    fi
  elif [ "$m_ordinary" -ge "$NORI_PRESSURE_ORDINARY_CRITICAL_PCT" ]; then
    state=critical
  else
    state=healthy
  fi
}

print_json() {
  local fs_uuid_json=null
  if [ "$m_uuid" != null ]; then
    fs_uuid_json=$(jq -n --arg u "$m_uuid" '$u')
  fi
  jq -n \
    --arg path "$1" \
    --arg fs_type "$m_type" \
    --argjson fs_uuid "$fs_uuid_json" \
    --argjson ordinary_used_pct "$m_ordinary" \
    --argjson metadata_used_bytes "$m_meta_used" \
    --argjson metadata_total_bytes "$m_meta_total" \
    --argjson metadata_used_pct "$m_meta_pct" \
    --argjson unallocated_bytes "$m_unalloc" \
    --arg state "$state" \
    '{
       path: $path,
       fs_type: $fs_type,
       fs_uuid: $fs_uuid,
       ordinary_used_pct: $ordinary_used_pct,
       metadata_used_bytes: $metadata_used_bytes,
       metadata_total_bytes: $metadata_total_bytes,
       metadata_used_pct: $metadata_used_pct,
       unallocated_bytes: $unallocated_bytes,
       state: $state
     }'
}

# The lock key is the filesystem identity, never the mountpoint: every
# subvolume/path of one physical filesystem shares one lock, so allocation
# maintenance and the snapshot writer serialize per filesystem.
fs_key() {
  local path=$1 type='' uuid='' dev=''
  type=$(fs_type_of "$path") || die "cannot read filesystem type of $path"
  if [ "$type" = btrfs ]; then
    uuid=$(btrfs_uuid "$path") || exit 1
    printf 'uuid-%s' "$uuid"
  else
    dev=$(fs_device_of "$path") || die "cannot read device number of $path"
    is_uint "$dev" || die "malformed device number for $path"
    printf 'dev-%s' "$dev"
  fi
}

prepare_lock() {
  local key=$1 file=
  mkdir -p -- "$NORI_PRESSURE_LOCK_DIR" || die "cannot create lock directory $NORI_PRESSURE_LOCK_DIR"
  file="$NORI_PRESSURE_LOCK_DIR/$key.lock"
  if [ ! -e "$file" ]; then
    (umask 0007 && : >"$file") || die "cannot create lock file $file"
    chgrp -- "$NORI_PRESSURE_LOCK_GROUP" "$file" ||
      die "cannot set group $NORI_PRESSURE_LOCK_GROUP on lock file $file"
  fi
  printf '%s' "$file"
}

cmd_with_lock() {
  [ "$#" -gt 0 ] || die "with-lock requires a path"
  local path=$1
  shift
  [ "$#" -gt 0 ] || die "with-lock requires a command"
  local lock_file='' fd=''
  lock_file=$(prepare_lock "$(fs_key "$path")") || exit 1
  exec {fd}<>"$lock_file" || die "cannot open lock file $lock_file"
  if ! flock -n "$fd"; then
    printf 'nori-storage-pressure: lock busy: %s\n' "$lock_file" >&2
    exit 75
  fi
  "$@"
}

balance_data() {
  local path=$1 usage=$2 out=
  # Canonical documented filter form for the installed btrfs-progs: one
  # comma-separated filter list on the data option (`-d[filters]`, no space in
  # between). Both `usage` and `limit` live in that single argument, so there is
  # no repeated-`-d` merge/last-option ambiguity.
  if ! out=$("$BTRFS_BIN" balance start \
    "-dusage=$usage,limit=$NORI_PRESSURE_MAINTENANCE_LIMIT" -- "$path" 2>&1); then
    printf 'nori-storage-pressure: data balance (usage<=%s%%, limit=%s) failed on %s: %s\n' \
      "$usage" "$NORI_PRESSURE_MAINTENANCE_LIMIT" "$path" "$out" >&2
    return 1
  fi
  [ -z "$out" ] || printf 'nori-storage-pressure: %s\n' "$out" >&2
}

# maintain_one PATH — bounded data-only maintenance of one filesystem.
# Pass 1 reclaims empty data block groups. Pass 2 (only when expansion
# headroom is below the target and workspace remains to compact safely) runs
# the explicit usage/limit compaction. Never a full balance, never a metadata
# profile conversion, never any deletion.
maintain_one() {
  local path=$1 uuid='' exop='' op='' lock_file='' fd=''
  local before=''
  uuid=$(btrfs_uuid "$path") || exit 1

  # Another exclusive filesystem operation (balance, resize, device add/
  # delete, qgroup rescan) already owns this filesystem — defer, never race.
  # The kernel counter is authoritative: a missing or unreadable counter means
  # the owner is unknown, which is not permission to start a balance, so it is
  # an actionable error rather than an implicit "free".
  exop="$SYSFS_BTRFS/$uuid/exclusive_operation"
  [ -e "$exop" ] ||
    die "cannot determine the exclusive-operation owner of $path ($exop is missing); refusing allocation maintenance"
  op=$(cat "$exop" 2>/dev/null) ||
    die "cannot read the exclusive-operation owner of $path ($exop); refusing allocation maintenance"
  if [ -z "$op" ]; then
    die "empty exclusive-operation marker for $path ($exop); refusing allocation maintenance"
  fi
  if [ "$op" != none ]; then
    printf 'nori-storage-pressure: deferring %s — exclusive filesystem operation "%s" owns it\n' \
      "$path" "$op" >&2
    return 0
  fi

  lock_file=$(prepare_lock "uuid-$uuid") || exit 1
  exec {fd}<>"$lock_file" || die "cannot open lock file $lock_file"
  if ! flock -n "$fd"; then
    printf 'nori-storage-pressure: deferring %s — another holder owns %s\n' "$path" "$lock_file" >&2
    exec {fd}>&-
    return 0
  fi

  balance_data "$path" 0 || {
    exec {fd}>&-
    return 1
  }
  measure "$path"
  if [ "$m_unalloc" -ge "$NORI_PRESSURE_HEADROOM_TARGET_BYTES" ]; then
    printf 'nori-storage-pressure: %s already has %s unallocated bytes (target %s) — no compaction needed\n' \
      "$path" "$m_unalloc" "$NORI_PRESSURE_HEADROOM_TARGET_BYTES" >&2
    exec {fd}>&-
    return 0
  fi
  if [ "$m_unalloc" -le "$NORI_PRESSURE_CRITICAL_WORKSPACE_BYTES" ]; then
    printf 'nori-storage-pressure: refusing further compaction of %s — only %s unallocated bytes remain (critical workspace %s); free data or add devices, do not delete\n' \
      "$path" "$m_unalloc" "$NORI_PRESSURE_CRITICAL_WORKSPACE_BYTES" >&2
    exec {fd}>&-
    return 75
  fi

  before=$m_unalloc
  balance_data "$path" "$NORI_PRESSURE_MAINTENANCE_USAGE" || {
    exec {fd}>&-
    return 1
  }
  measure "$path"
  printf 'nori-storage-pressure: %s unallocated %s -> %s bytes\n' "$path" "$before" "$m_unalloc" >&2
  exec {fd}>&-
  return 0
}

cmd_maintain() {
  [ "$#" -gt 0 ] || die "maintain requires at least one path"
  local path='' type='' key='' failed=0 deferred=0 status=0
  declare -A seen=()
  for path in "$@"; do
    # An unreadable path is reported and skipped, never allowed to abort the
    # remaining filesystems; the run still fails so the failure is visible.
    if ! type=$(fs_type_of "$path"); then
      printf 'nori-storage-pressure: cannot read filesystem type of %s — skipping it\n' "$path" >&2
      failed=1
      continue
    fi
    if [ "$type" != btrfs ]; then
      printf 'nori-storage-pressure: %s is %s, not btrfs — no allocation maintenance applies\n' \
        "$path" "$type" >&2
      continue
    fi
    if ! key=$(fs_key "$path"); then
      printf 'nori-storage-pressure: cannot resolve filesystem identity of %s — skipping it\n' "$path" >&2
      failed=1
      continue
    fi
    if [ -n "${seen[$key]:-}" ]; then
      printf 'nori-storage-pressure: %s shares filesystem %s with an earlier path — maintained once\n' \
        "$path" "$key" >&2
      continue
    fi
    seen[$key]=1
    # One filesystem per subshell: a measurement or balance failure (or the
    # fail-closed owner check) stops that filesystem only, and the lock is
    # released as soon as the subshell exits.
    if (maintain_one "$path"); then
      status=0
    else
      status=$?
    fi
    case "$status" in
      0) ;;
      75) deferred=1 ;;
      *)
        printf 'nori-storage-pressure: maintenance failed for %s — continuing with the remaining filesystems\n' \
          "$path" >&2
        failed=1
        ;;
    esac
  done
  [ "$failed" -eq 0 ] || return 1
  [ "$deferred" -eq 0 ] || return 75
  return 0
}

main() {
  local cmd=${1:-}
  [ -n "$cmd" ] || die "usage: nori-storage-pressure {probe|check|with-lock|maintain} ..."
  shift
  case "$cmd" in
    probe)
      [ "$#" -eq 1 ] || die "probe requires exactly one path"
      measure "$1"
      classify
      print_json "$1"
      ;;
    check)
      [ "$#" -eq 1 ] || die "check requires exactly one path"
      measure "$1"
      classify
      print_json "$1"
      if [ "$state" = critical ]; then
        exit 75
      fi
      ;;
    with-lock) cmd_with_lock "$@" ;;
    maintain) cmd_maintain "$@" ;;
    *) die "unknown subcommand: $cmd" ;;
  esac
}

main "$@"
