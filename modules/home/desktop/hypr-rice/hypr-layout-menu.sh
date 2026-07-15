#!/usr/bin/env bash
set -euo pipefail

fuzzel_bin=${FUZZEL_BIN:-$(command -v fuzzel || true)}
hypr_layout_bin=${HYPR_LAYOUT_BIN:-$(command -v hypr-layout || true)}

for entry in "fuzzel:$fuzzel_bin" "hypr-layout:$hypr_layout_bin"; do
  name=${entry%%:*}
  path=${entry#*:}
  if [[ -z $path || ! -x $path ]]; then
    printf 'hypr-layout-menu: %s is not available in PATH\n' "$name" >&2
    exit 127
  fi
done

choose() {
  local output status
  set +e
  output=$("$@")
  status=$?
  set -e
  [[ $status -eq 1 ]] && return 1
  [[ $status -eq 0 ]] || exit "$status"
  printf '%s' "$output"
}

presets=$'1 1\n1 2 1\nrepeat(1,5)\na b; a d; c c\nCustom…\nreset'
if ! choice=$(printf '%s\n' "$presets" | choose "$fuzzel_bin" --dmenu --only-match --prompt 'layout: '); then
  exit 0
fi
[[ -n $choice ]] || exit 0

if [[ $choice == 'Custom…' ]]; then
  if ! choice=$(choose "$fuzzel_bin" --dmenu --prompt-only 'layout expression: '); then
    exit 0
  fi
  [[ -n $choice ]] || exit 0
fi

"$hypr_layout_bin" "$choice"
