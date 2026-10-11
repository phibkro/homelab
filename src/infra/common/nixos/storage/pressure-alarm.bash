# shellcheck shell=bash
#
# nori disk-alert — allocation-pressure alarm body.
#
# Executed by disk-alert.service (this is that unit's implementation file; it
# lives beside the pressure CLI it drives so the measurement, the
# classification and the alert policy stay one construct). It decides:
#
#   critical   urgent alert with the allocation measurements — the existing
#              delivery behaviour (require-delivery, failed unit on failure)
#   warning    warning alert ONCE per filesystem, gated by a stamp file in the
#              unit's runtime directory; the stamp is written only after a
#              delivery that succeeded, and cleared on healthy/critical so a
#              recovery re-arms the early warning
#   error      urgent alert + failed unit; a failed measurement is never
#              reported as healthy
#
# Contract — every value is supplied by the unit, nothing here invents policy:
#   PRESSURE_CLI                 absolute path to bin/nori-storage-pressure
#   PRESSURE_ALERT_CMD           absolute path to bin/nori-alert
#   PRESSURE_HOST                hostname used in alert titles
#   PRESSURE_STATE_DIR           runtime dir holding the warning stamps
#   PRESSURE_MUTED_CRITICAL_MOUNTPOINTS  JSON array of critical-notification mutes
#   PRESSURE_META_WARN_PCT       metadata warning threshold (reason text)
#   PRESSURE_META_CRIT_PCT       metadata critical threshold (reason text)
#   PRESSURE_WARN_WORKSPACE_BYTES  warning expansion workspace (reason text)
#   PRESSURE_CRIT_WORKSPACE_BYTES  critical expansion workspace (reason text)
#   argv                         mountpoints to measure (one per filesystem)
#
# Warning stamps are keyed by filesystem identity (btrfs UUID), so subvolume
# paths of one physical filesystem never produce two warnings.

export LC_ALL=C

: "${PRESSURE_CLI:?disk-alert: PRESSURE_CLI must be set}"
: "${PRESSURE_ALERT_CMD:?disk-alert: PRESSURE_ALERT_CMD must be set}"
: "${PRESSURE_HOST:?disk-alert: PRESSURE_HOST must be set}"
: "${PRESSURE_STATE_DIR:?disk-alert: PRESSURE_STATE_DIR must be set}"
: "${PRESSURE_MUTED_CRITICAL_MOUNTPOINTS:?disk-alert: critical notification policy must be set}"
: "${PRESSURE_META_WARN_PCT:?disk-alert: PRESSURE_META_WARN_PCT must be set}"
: "${PRESSURE_META_CRIT_PCT:?disk-alert: PRESSURE_META_CRIT_PCT must be set}"
: "${PRESSURE_WARN_WORKSPACE_BYTES:?disk-alert: PRESSURE_WARN_WORKSPACE_BYTES must be set}"
: "${PRESSURE_CRIT_WORKSPACE_BYTES:?disk-alert: PRESSURE_CRIT_WORKSPACE_BYTES must be set}"

die() {
  printf 'disk-alert: %s\n' "$*" >&2
  exit 1
}

# Filesystem identity of a measurement, for the warning stamp name.
stamp_key() { # JSON PATH
  local json=$1 path=$2 uuid=''
  uuid=$(printf '%s' "$json" | jq -r '.fs_uuid // empty')
  if [ -n "$uuid" ]; then
    printf '%s' "$uuid"
  else
    printf '%s' "$path" | tr '/' '_'
  fi
}

critical_body() { # JSON
  printf '%s' "$1" | jq -r \
    --arg host "$PRESSURE_HOST" \
    --argjson meta_crit_pct "$PRESSURE_META_CRIT_PCT" \
    --argjson crit_workspace "$PRESSURE_CRIT_WORKSPACE_BYTES" \
    '("Filesystem \(.path) on \($host) is \(.ordinary_used_pct)% used." +
     (if .metadata_used_pct == null then ""
      else " btrfs metadata \(.metadata_used_pct)% used (\(.metadata_used_bytes) of \(.metadata_total_bytes) bytes), device unallocated \(.unallocated_bytes) bytes (metadata critical \($meta_crit_pct)%, critical workspace \($crit_workspace) bytes)."
      end) +
     " See docs/runbooks/storage-full.md.")'
}

warning_body() { # JSON
  printf '%s' "$1" | jq -r \
    --arg host "$PRESSURE_HOST" \
    --argjson meta_warn_pct "$PRESSURE_META_WARN_PCT" \
    --argjson warn_workspace "$PRESSURE_WARN_WORKSPACE_BYTES" \
    '("Filesystem \(.path) on \($host) is \(.ordinary_used_pct)% used." +
     (if .metadata_used_pct == null then ""
      else " btrfs metadata \(.metadata_used_pct)% used (\(.metadata_used_bytes) of \(.metadata_total_bytes) bytes), device unallocated \(.unallocated_bytes) bytes (metadata warning \($meta_warn_pct)%, warning workspace \($warn_workspace) bytes)."
      end) +
     " Expansion workspace is scarce; the bounded maintenance timer reclaims what it can, and this is not critical yet. See docs/runbooks/storage-full.md.")'
}

alarm_json_pct() { # JSON -> ordinary percentage
  printf '%s' "$1" | jq -r '.ordinary_used_pct'
}

# handle_mount PATH — returns nonzero when this mountpoint needs attention
# reported as a unit failure (delivery failure, measurement error).
handle_mount() {
  local mount=$1 json='' code=0 err='' state='' key='' stamp=''
  err=$(mktemp)
  if json=$("$PRESSURE_CLI" check "$mount" 2>"$err"); then
    code=0
  else
    code=$?
  fi

  case "$code" in
    0)
      state=$(printf '%s' "$json" | jq -r '.state')
      key=$(stamp_key "$json" "$mount")
      stamp="$PRESSURE_STATE_DIR/$key.warning"
      case "$state" in
        warning)
          if [ "$(cat "$stamp" 2>/dev/null || true)" = warning ]; then
            printf 'disk-alert: %s is still in allocation warning; already notified\n' "$mount" >&2
          elif "$PRESSURE_ALERT_CMD" \
            --audience operator \
            --severity warning \
            --category disk \
            --require-delivery \
            --title "$PRESSURE_HOST: disk pressure warning ($mount $(alarm_json_pct "$json")%)" \
            --body "$(warning_body "$json")"; then
            printf 'warning' >"$stamp"
          else
            printf 'disk-alert: warning alert delivery failed for %s; not marking it notified\n' "$mount" >&2
            rm -f "$err"
            return 1
          fi
          ;;
        *)
          # healthy (or any other non-critical state): recovery re-arms the
          # early warning for the next warning episode.
          rm -f "$stamp"
          ;;
      esac
      ;;
    75)
      key=$(stamp_key "$json" "$mount")
      rm -f "$PRESSURE_STATE_DIR/$key.warning"
      if printf '%s' "$PRESSURE_MUTED_CRITICAL_MOUNTPOINTS" | jq -e --arg path "$mount" 'index($path) != null' >/dev/null; then
        printf 'disk-alert: critical notification muted for %s; pressure remains critical\n' "$mount" >&2
        rm -f "$err"
        return 0
      fi
      if ! "$PRESSURE_ALERT_CMD" \
        --audience operator \
        --severity urgent \
        --category disk \
        --require-delivery \
        --title "$PRESSURE_HOST: disk critical ($mount $(alarm_json_pct "$json")%)" \
        --body "$(critical_body "$json")"; then
        printf 'disk-alert: critical alert delivery failed for %s\n' "$mount" >&2
        rm -f "$err"
        return 1
      fi
      ;;
    1)
      printf 'disk-alert: cannot measure %s: %s\n' "$mount" "$(cat "$err")" >&2
      if ! "$PRESSURE_ALERT_CMD" \
        --audience operator \
        --severity urgent \
        --category disk \
        --require-delivery \
        --title "$PRESSURE_HOST: disk measurement failed ($mount)" \
        --body "Filesystem $mount on $PRESSURE_HOST could not be measured: $(cat "$err"). Its allocation state is unknown until measuring succeeds — check the mount. See docs/runbooks/storage-full.md."; then
        printf 'disk-alert: measurement-failure alert delivery failed for %s\n' "$mount" >&2
      fi
      rm -f "$err"
      return 1
      ;;
    *)
      printf 'disk-alert: unexpected exit %s measuring %s\n' "$code" "$mount" >&2
      rm -f "$err"
      return 1
      ;;
  esac

  rm -f "$err"
  return 0
}

main() {
  [ "$#" -gt 0 ] || die "no mountpoints to measure"
  local failed=0 mount
  for mount in "$@"; do
    handle_mount "$mount" || failed=1
  done
  return "$failed"
}
