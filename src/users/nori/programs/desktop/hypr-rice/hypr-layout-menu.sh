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

preset_choices=$'1 1\n1 2 1\nrepeat(1,5)\na b; a d; c c'

choose_preset() {
  printf '%s\n' "$preset_choices" |
    choose "$fuzzel_bin" --dmenu --only-match --prompt 'layout: '
}

choose_custom() {
  choose "$fuzzel_bin" --dmenu --prompt-only 'layout expression: '
}

mode=${1:-menu}
[[ $# -le 1 ]] || {
  printf 'usage: hypr-layout-menu [menu|presets|custom]\n' >&2
  exit 64
}

case $mode in
  presets)
    if ! choice=$(choose_preset); then
      exit 0
    fi
    ;;
  custom)
    if ! choice=$(choose_custom); then
      exit 0
    fi
    ;;
  menu)
    choices="$preset_choices"$'\nCustom…\nreset'
    if ! choice=$(printf '%s\n' "$choices" | choose "$fuzzel_bin" --dmenu --only-match --prompt 'layout: '); then
      exit 0
    fi
    if [[ $choice == 'Custom…' ]]; then
      if ! choice=$(choose_custom); then
        exit 0
      fi
    fi
    ;;
  *)
    printf 'usage: hypr-layout-menu [menu|presets|custom]\n' >&2
    exit 64
    ;;
esac

[[ -n $choice ]] || exit 0
"$hypr_layout_bin" "$choice"
