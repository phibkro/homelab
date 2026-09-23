#!/usr/bin/env bash
set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
queue=$tmp/queue
fuzzel_calls=$tmp/fuzzel-calls
layout_calls=$tmp/layout-calls

printf '#!%s\n' "$BASH" >"$tmp/fuzzel"
cat >>"$tmp/fuzzel" <<'EOF'
set -euo pipefail
printf '%s\0' "$@" >>"$LAYOUT_MENU_FUZZEL_CALLS"
mapfile -t responses <"$LAYOUT_MENU_QUEUE"
[[ ${#responses[@]} -gt 0 ]] || exit 64
IFS='|' read -r status output <<<"${responses[0]}"
: >"$LAYOUT_MENU_QUEUE"
if [[ ${#responses[@]} -gt 1 ]]; then
  printf '%s\n' "${responses[@]:1}" >"$LAYOUT_MENU_QUEUE"
fi
printf '%s' "$output"
exit "$status"
EOF
chmod +x "$tmp/fuzzel"

printf '#!%s\n' "$BASH" >"$tmp/hypr-layout"
cat >>"$tmp/hypr-layout" <<'EOF'
set -euo pipefail
printf '%s\0' "$@" >>"$LAYOUT_MENU_LAYOUT_CALLS"
EOF
chmod +x "$tmp/hypr-layout"

responses() {
  printf '%s\n' "$@" >"$queue"
}

run() {
  : >"$fuzzel_calls"
  : >"$layout_calls"
  LAYOUT_MENU_QUEUE="$queue" \
    LAYOUT_MENU_FUZZEL_CALLS="$fuzzel_calls" \
    LAYOUT_MENU_LAYOUT_CALLS="$layout_calls" \
    FUZZEL_BIN="$tmp/fuzzel" \
    HYPR_LAYOUT_BIN="$tmp/hypr-layout" \
    bash "$script" "$@"
}

layout_args() {
  mapfile -d '' -t captured <"$layout_calls"
}

fuzzel_args() {
  mapfile -d '' -t menu_calls <"$fuzzel_calls"
}

responses '0|1 2 1'
run
layout_args
[[ ${#captured[@]} -eq 1 && ${captured[0]} == '1 2 1' ]]
fuzzel_args
[[ " ${menu_calls[*]} " == *' --only-match '* ]]

responses '0|Custom…' '0|1 1 1'
run
layout_args
[[ ${#captured[@]} -eq 1 && ${captured[0]} == '1 1 1' ]]
fuzzel_args
[[ " ${menu_calls[*]} " == *' --prompt-only '* ]]

responses '0|reset'
run
layout_args
[[ ${#captured[@]} -eq 1 && ${captured[0]} == reset ]]

responses '1|'
run
[[ ! -s $layout_calls ]]

responses '0|Custom…' '1|'
run
[[ ! -s $layout_calls ]]

responses '0|Custom…' '0|'
run
[[ ! -s $layout_calls ]]

responses '0|repeat(1,5)'
run presets
layout_args
[[ ${#captured[@]} -eq 1 && ${captured[0]} == 'repeat(1,5)' ]]

responses '0|a b; c d'
run custom
layout_args
[[ ${#captured[@]} -eq 1 && ${captured[0]} == 'a b; c d' ]]
fuzzel_args
[[ " ${menu_calls[*]} " == *' --prompt-only '* ]]

if responses '0|anything' && run unknown 2>/dev/null; then
  echo 'hypr-layout-menu accepted an unknown mode' >&2
  exit 1
fi

echo 'hypr-layout-menu behavior tests passed'
