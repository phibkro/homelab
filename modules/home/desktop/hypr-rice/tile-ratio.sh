#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
  printf '%s\n' 'usage: tile-ratio [RATIO]' >&2
  exit 2
}

[[ $# -le 1 ]] || usage

hyprctl_bin=${HYPRCTL_BIN:-$(command -v hyprctl || true)}
fuzzel_bin=${FUZZEL_BIN:-$(command -v fuzzel || true)}
notify_send_bin=${NOTIFY_SEND_BIN:-$(command -v notify-send || true)}
sleep_bin=${SLEEP_BIN:-$(command -v sleep || true)}
jq_bin=${JQ_BIN:-$(command -v jq || true)}
awk_bin=${AWK_BIN:-$(command -v awk || true)}

for entry in \
  "hyprctl:$hyprctl_bin" \
  "fuzzel:$fuzzel_bin" \
  "notify-send:$notify_send_bin" \
  "sleep:$sleep_bin" \
  "jq:$jq_bin" \
  "awk:$awk_bin"; do
  name=${entry%%:*}
  path=${entry#*:}
  if [[ -z $path || ! -x $path ]]; then
    printf 'tile-ratio: %s is not available in PATH\n' "$name" >&2
    exit 127
  fi
done

fail() {
  local message=$1
  printf 'tile-ratio: %s\n' "$message" >&2
  "$notify_send_bin" -a tile-ratio 'Tile ratio' "$message" >/dev/null 2>&1 || true
  return 1
}

parse_ratio() {
  local raw=$1 numerator denominator percent normalized
  [[ ${#raw} -le 64 ]] || return 1

  if [[ $raw =~ ^0\.[0-9]+$ ]]; then
    normalized=$raw
  elif [[ $raw =~ ^([0-9]+)/([0-9]+)$ ]]; then
    numerator=${BASH_REMATCH[1]}
    denominator=${BASH_REMATCH[2]}
    [[ $denominator != 0 ]] || return 1
    normalized=$(
      "$awk_bin" -v numerator="$numerator" -v denominator="$denominator" \
        'BEGIN { value = numerator / denominator; if (!(value > 0 && value < 1)) exit 1; printf "%.17g", value }'
    ) || return 1
  elif [[ $raw =~ ^([0-9]+([.][0-9]+)?)%$ ]]; then
    percent=${BASH_REMATCH[1]}
    normalized=$(
      "$awk_bin" -v percent="$percent" \
        'BEGIN { value = percent / 100; if (!(value > 0 && value < 1)) exit 1; printf "%.17g", value }'
    ) || return 1
  else
    return 1
  fi

  "$awk_bin" -v value="$normalized" \
    'BEGIN { if (!(value > 0 && value < 1)) exit 1; printf "%.17g", value }'
}

focused_window=
focused_address=
focused_workspace_id=
focused_monitor_id=
focused_width=
monitor_width=

load_focus() {
  local layout mapped floating
  if ! focused_window=$("$hyprctl_bin" -j activewindow 2>/dev/null); then
    fail 'could not query the focused window'
    return 1
  fi

  focused_address=$(printf '%s' "$focused_window" | "$jq_bin" -r '.address // empty')
  mapped=$(printf '%s' "$focused_window" | "$jq_bin" -r '.mapped == true')
  floating=$(printf '%s' "$focused_window" | "$jq_bin" -r '.floating == true')
  focused_workspace_id=$(printf '%s' "$focused_window" | "$jq_bin" -r '.workspace.id // empty')
  focused_monitor_id=$(printf '%s' "$focused_window" | "$jq_bin" -r '.monitor // empty')
  focused_width=$(printf '%s' "$focused_window" | "$jq_bin" -r '.size[0] // empty')

  if [[ -z $focused_address || $mapped != true || $floating != false || -z $focused_workspace_id || -z $focused_monitor_id || -z $focused_width ]]; then
    fail 'no mapped tiled focused window'
    return 1
  fi

  if ! layout=$("$hyprctl_bin" -j workspaces | "$jq_bin" -r --argjson id "$focused_workspace_id" '.[] | select(.id == $id) | .tiledLayout' | head -n1); then
    fail 'could not query the focused window workspace'
    return 1
  fi
  if [[ $layout == lua:rice ]]; then
    fail 'workspace uses lua:rice; run "hypr-layout reset" before setting a focused-window ratio'
    return 1
  fi
  if [[ $layout != dwindle ]]; then
    fail "focused-window ratio requires dwindle (current layout: ${layout:-unknown})"
    return 1
  fi

  if ! monitor_width=$("$hyprctl_bin" -j monitors | "$jq_bin" -r --argjson id "$focused_monitor_id" '.[] | select(.id == $id) | .width' | head -n1); then
    fail 'could not query the focused monitor'
    return 1
  fi
  if [[ -z $monitor_width || $monitor_width == null ]]; then
    fail 'could not query the focused monitor width'
    return 1
  fi
}

current_width() {
  local current address width
  current=$("$hyprctl_bin" -j activewindow)
  address=$(printf '%s' "$current" | "$jq_bin" -r '.address // empty')
  width=$(printf '%s' "$current" | "$jq_bin" -r '.size[0] // empty')
  if [[ $address != "$focused_address" || -z $width ]]; then
    fail 'focused window changed during calibration; geometry may already have changed'
    return 1
  fi
  printf '%s' "$width"
}

ratio=
if [[ $# -eq 1 ]]; then
  if ! ratio=$(parse_ratio "$1"); then
    fail "invalid absolute ratio: $1"
    exit 2
  fi
else
  load_focus || exit 1
  presets=$'1/2\n1/3\n2/3\n1/4\n3/4\n1/5\n2/5'
  set +e
  choice=$(printf '%s\n' "$presets" | "$fuzzel_bin" --dmenu --prompt 'absolute ratio: ')
  status=$?
  set -e
  [[ $status -eq 1 ]] && exit 0
  [[ $status -eq 0 ]] || exit "$status"
  [[ -n $choice ]] || exit 0
  if ! ratio=$(parse_ratio "$choice"); then
    fail "invalid absolute ratio: $choice"
    exit 2
  fi
fi

load_focus || exit 1

gaps_out=${TILE_RATIO_GAPS_OUT:-8}
usable_width=$("$awk_bin" -v width="$monitor_width" -v gaps="$gaps_out" \
  'BEGIN { value = width - 2 * gaps; if (!(value > 0)) exit 1; printf "%.17g", value }') || {
  fail 'focused monitor has no usable width'
  exit 1
}
target_width=$("$awk_bin" -v ratio="$ratio" -v usable="$usable_width" \
  'BEGIN { value = ratio * usable; if (!(value > 0)) exit 1; printf "%.17g", value }') || {
  fail 'could not calculate target width'
  exit 1
}

probe=0.2
width_before=$(current_width) || exit 1
"$hyprctl_bin" dispatch "hl.dsp.layout(\"splitratio $probe\")" >/dev/null
"$sleep_bin" 0.05
width_after=$(current_width) || exit 1
if ! slope=$("$awk_bin" -v before="$width_before" -v after="$width_after" -v probe="$probe" \
  'BEGIN { value = (after - before) / probe; if (!(value < 0 || value > 0)) exit 1; printf "%.17g", value }'); then
  fail 'probe produced no measurable width change; geometry may already have changed'
  exit 1
fi

converged=false
for _ in 1 2 3 4 5; do
  width=$(current_width) || exit 1
  if "$awk_bin" -v width="$width" -v target="$target_width" \
      'BEGIN { delta = target - width; if (delta < 0) delta = -delta; exit !(delta < 3) }'; then
    converged=true
    break
  fi

  delta=$("$awk_bin" -v width="$width" -v target="$target_width" -v slope="$slope" \
    'BEGIN { value = (target - width) / slope; if (!(value < 0 || value > 0)) exit 1; printf "%.17g", value }') || {
    fail 'could not calculate a corrective split ratio; geometry may already have changed'
    exit 1
  }
  "$hyprctl_bin" dispatch "hl.dsp.layout(\"splitratio $delta\")" >/dev/null
  "$sleep_bin" 0.05
done

if [[ $converged != true ]]; then
  width=$(current_width) || exit 1
  if "$awk_bin" -v width="$width" -v target="$target_width" \
      'BEGIN { delta = target - width; if (delta < 0) delta = -delta; exit !(delta < 3) }'; then
    converged=true
  fi
fi

if [[ $converged != true ]]; then
  fail 'failed to converge within five corrections; geometry may already have changed'
  exit 1
fi
