#!/usr/bin/env bash
set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
state=$tmp/state
calls=$tmp/calls

printf '#!%s\n' "$BASH" >"$tmp/hyprctl"
cat >>"$tmp/hyprctl" <<'EOF'
set -euo pipefail
printf '%s\0' "$@" >>"$TILE_RATIO_CALLS"

case "$*" in
  '-j activewindow')
    if [[ ${TILE_RATIO_NO_WINDOW:-0} == 1 ]]; then
      printf '{}\n'
    else
      width=$(<"$TILE_RATIO_STATE")
      printf '{"address":"0xabc","mapped":true,"floating":false,"workspace":{"id":1,"name":"1"},"monitor":0,"size":[%s,700]}\n' "$width"
    fi
    ;;
  '-j workspaces')
    printf '[{"id":1,"name":"1","tiledLayout":"%s"}]\n' "${TILE_RATIO_LAYOUT:-dwindle}"
    ;;
  '-j monitors')
    printf '[{"id":0,"focused":true,"width":1000}]\n'
    ;;
  dispatch*)
    command=${2-}
    if [[ $command =~ splitratio[[:space:]](-?[0-9]+([.][0-9]+)?) ]]; then
      delta=${BASH_REMATCH[1]}
      dispatch_count=0
      [[ -f $TILE_RATIO_STATE.count ]] && dispatch_count=$(<"$TILE_RATIO_STATE.count")
      dispatch_count=$((dispatch_count + 1))
      printf '%s' "$dispatch_count" >"$TILE_RATIO_STATE.count"
      width=$(<"$TILE_RATIO_STATE")
      if [[ ${TILE_RATIO_ZERO_SLOPE:-0} == 1 ]]; then
        next=$width
      elif [[ ${TILE_RATIO_STALL_AFTER_PROBE:-0} == 1 && $dispatch_count -gt 1 ]]; then
        next=$width
      else
        next=$(awk -v width="$width" -v delta="$delta" 'BEGIN { printf "%.6f", width + delta * 100 }')
      fi
      printf '%s' "$next" >"$TILE_RATIO_STATE"
      printf 'ok\n'
    else
      printf 'unexpected dispatch: %s\n' "$command" >&2
      exit 64
    fi
    ;;
  *)
    printf 'unexpected hyprctl args: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF
chmod +x "$tmp/hyprctl"

printf '#!%s\n' "$BASH" >"$tmp/fuzzel"
cat >>"$tmp/fuzzel" <<'EOF'
set -euo pipefail
printf '%s\0' "$@" >>"$TILE_RATIO_CALLS"
printf '%s' "${TILE_RATIO_FUZZEL_CHOICE:-}"
exit "${TILE_RATIO_FUZZEL_STATUS:-0}"
EOF
chmod +x "$tmp/fuzzel"

printf '#!%s\n' "$BASH" >"$tmp/sleep"
cat >>"$tmp/sleep" <<'EOF'
exit 0
EOF
chmod +x "$tmp/sleep"

run() {
  : >"$calls"
  printf '300' >"$state"
  rm -f "$state.count"
  TILE_RATIO_STATE="$state" \
    TILE_RATIO_CALLS="$calls" \
    HYPRCTL_BIN="$tmp/hyprctl" \
    FUZZEL_BIN="$tmp/fuzzel" \
    SLEEP_BIN="$tmp/sleep" \
    bash "$script" "$@"
}

expect_width() {
  awk -v actual="$(<"$state")" -v expected="$1" 'BEGIN { exit !((actual - expected < 0 ? expected - actual : actual - expected) < 0.01) }'
}

expect_no_dispatch() {
  if tr '\0' '\n' <"$calls" | grep -q '^dispatch$'; then
    printf '%s\n' 'unexpected splitratio dispatch' >&2
    exit 1
  fi
}

for ratio in 2/5 0.4 40%; do
  run "$ratio" >/dev/null
  expect_width 393.6
  [[ $(<"$state.count") -eq 2 ]]
done

for invalid in 2 0 1 0% 100% -0.4 +0.4 4/0 2/5junk 4e-1 ' 0.4'; do
  if run "$invalid" >"$tmp/out" 2>"$tmp/err"; then
    printf 'accepted invalid ratio: %s\n' "$invalid" >&2
    exit 1
  fi
  expect_no_dispatch
done

TILE_RATIO_FUZZEL_STATUS=1 run >/dev/null
expect_no_dispatch
TILE_RATIO_FUZZEL_STATUS=0 TILE_RATIO_FUZZEL_CHOICE='' run >/dev/null
expect_no_dispatch
TILE_RATIO_FUZZEL_STATUS=0 TILE_RATIO_FUZZEL_CHOICE='1/2' run >/dev/null
expect_width 492

if TILE_RATIO_NO_WINDOW=1 run 1/2 >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -q 'no mapped tiled focused window' "$tmp/err"
expect_no_dispatch

if TILE_RATIO_LAYOUT=lua:rice run 1/2 >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -q 'hypr-layout reset' "$tmp/err"
expect_no_dispatch

if TILE_RATIO_LAYOUT=master run 1/2 >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -q 'requires dwindle' "$tmp/err"
expect_no_dispatch

if TILE_RATIO_ZERO_SLOPE=1 run 1/2 >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -q 'probe produced no measurable width change' "$tmp/err"
[[ $(<"$state.count") -eq 1 ]]

if TILE_RATIO_STALL_AFTER_PROBE=1 run 1/2 >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
grep -q 'failed to converge' "$tmp/err"
[[ $(<"$state.count") -eq 6 ]]

if run 1/2 extra >"$tmp/out" 2>"$tmp/err"; then exit 1; fi
expect_no_dispatch

echo 'tile-ratio behavior tests passed'
