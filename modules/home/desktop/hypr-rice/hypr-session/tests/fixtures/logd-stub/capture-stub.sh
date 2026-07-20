#!/usr/bin/env bash
# Stub capture command for logd.bats — stands in for capture.sh so
# logd.bats never talks to a real compositor. Emits a minimal but
# valid-shaped v1 snapshot with an incrementing call counter (lets tests
# assert debounce coalescing by call count) and can be forced to fail on
# demand (lets tests assert logd survives a transient capture failure).
#
# Env:
#   HYPR_SESSION_STUB_CALLS_FILE  path this script increments once per
#                                 invocation (created if absent).
#   HYPR_SESSION_STUB_FAIL_FLAG   optional; if set and the named file
#                                 exists, exit 1 instead of emitting a
#                                 snapshot (still counts the call).
set -euo pipefail

: "${HYPR_SESSION_STUB_CALLS_FILE:?capture-stub: HYPR_SESSION_STUB_CALLS_FILE not set}"

count=0
[[ -f $HYPR_SESSION_STUB_CALLS_FILE ]] && count=$(<"$HYPR_SESSION_STUB_CALLS_FILE")
count=$((count + 1))
printf '%s' "$count" >"$HYPR_SESSION_STUB_CALLS_FILE"

if [[ -n ${HYPR_SESSION_STUB_FAIL_FLAG-} && -f $HYPR_SESSION_STUB_FAIL_FLAG ]]; then
  echo "capture-stub: forced failure (call $count)" >&2
  exit 1
fi

printf '{"version":1,"captured_at":"2026-07-20T00:00:00Z","call":%s,"monitors":[],"focus":{"focused_window":null,"monitors":[]},"windows":[]}\n' "$count"
