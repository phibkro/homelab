#!/usr/bin/env bash
# Emits ONE full snapshot (schema v1) of the current Hyprland compositor
# state to stdout, as JSON. Pure query — never mutates window/workspace
# state, never called during shutdown (see
# docs/specs/2026-07-20-hypr-session-persistence-design.md § Capture).
#
# Snapshots are FULL, not deltas: apps are non-deterministic replayers, so
# delta-folding has no sound apply operation.
#
# Requires on PATH: hyprctl, jq, bash (associative arrays), coreutils
# (readlink, date, tr). Nix wrapping closes over these; login PATH is thin.
#
# Env:
#   HYPRLAND_INSTANCE_SIGNATURE  which compositor instance hyprctl targets.
#                                 Passed through untouched — never read or
#                                 overridden here — so tests can point it at
#                                 an isolated instance (or the PATH-shim
#                                 hyprctl stub, which ignores it entirely).
#   HYPR_SESSION_TEST_FIXTURES_DIR  consumed only by the tests/bin/hyprctl
#                                 stub, not by this script.
#   HYPR_SESSION_STATE_DIR       unused here — capture.sh has no state of
#                                 its own to persist (it only prints to
#                                 stdout); honored for interface parity with
#                                 the daemon/CLI that own log.jsonl / named/.
set -euo pipefail

if ! command -v hyprctl >/dev/null 2>&1; then
  echo "capture.sh: hyprctl not found on PATH" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

# Per-pid process enrichment, cached so a multi-window single-pid app (e.g.
# several ghostty windows) reads /proc once and every window sharing that
# pid gets the identical process object. cwd_cache/cmdline_cache hold the
# same two facts unencoded — compute_identity needs them as plain values,
# not re-decoded from the composed JSON blob every cache hit.
declare -A proc_cache
declare -A cwd_cache
declare -A cmdline_cache

compute_process() {
  local pid="$1"
  if [[ ! -r /proc/$pid/cmdline ]]; then
    proc_cache[$pid]=null
    return
  fi
  local cwd cmdline_json
  cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null) || cwd=""
  cmdline_json=$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null |
    jq -R -s 'split("\n") | map(select(length > 0))') || cmdline_json='[]'
  cwd_cache[$pid]=$cwd
  cmdline_cache[$pid]=$cmdline_json
  proc_cache[$pid]=$(jq -nc --arg cwd "$cwd" --argjson cmdline "$cmdline_json" \
    '{cwd: $cwd, cmdline: $cmdline}')
}

# Identity adapters — driven by lib.sh's adapter table (the same
# vocabulary restore.sh's launch-once/match-strategy adapters consult),
# answering "what IS this window" (a stable label restore can match on)
# rather than "how do I respawn it". Classes with no adapter entry get
# identity: null, even when process data is available.
compute_identity() {
  local class="$1" cmdline_json="$2" cwd="$3"
  local kind
  kind=$(adapter_identity_kind "$class")
  case "$kind" in
  terminal)
    jq -nc --arg v "$cwd" '{kind: "terminal", value: $v}'
    ;;
  editor)
    local dir
    dir=$(adapter_first_existing_arg -d "$cmdline_json") || true
    if [[ -n $dir ]]; then
      jq -nc --arg v "$dir" '{kind: "editor", value: $v}'
    else
      echo null
    fi
    ;;
  media)
    local file
    file=$(adapter_first_existing_arg -f "$cmdline_json") || true
    if [[ -n $file ]]; then
      jq -nc --arg v "$file" '{kind: "media", value: $v}'
    else
      echo null
    fi
    ;;
  *)
    echo null
    ;;
  esac
}

clients=$(hyprctl clients -j)
monitors=$(hyprctl monitors -j)
activewindow=$(hyprctl activewindow -j)
captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

windows=()
while IFS= read -r win; do
  IFS=$'\t' read -r address class title pid floating workspace_name < <(
    jq -r '[.address, .class, .title, .pid, .floating, .workspace.name] | @tsv' <<<"$win"
  )

  if [[ $floating == "true" ]]; then
    geometry_json=$(jq -c '{x: .at[0], y: .at[1], width: .size[0], height: .size[1]}' <<<"$win")
  else
    geometry_json=null
  fi

  if [[ -z ${proc_cache[$pid]+set} ]]; then
    compute_process "$pid"
  fi
  process_json=${proc_cache[$pid]}

  if [[ $process_json == "null" ]]; then
    identity_json=null
  else
    identity_json=$(compute_identity "$class" "${cmdline_cache[$pid]}" "${cwd_cache[$pid]}")
  fi

  windows+=("$(jq -nc \
    --arg address "$address" \
    --arg class "$class" \
    --arg title "$title" \
    --arg workspace "$workspace_name" \
    --argjson floating "$floating" \
    --argjson geometry "$geometry_json" \
    --argjson process "$process_json" \
    --argjson identity "$identity_json" \
    '{address: $address, class: $class, title: $title, workspace: $workspace,
      floating: $floating, geometry: $geometry, process: $process, identity: $identity}')")
done < <(jq -c '.[]' <<<"$clients")

if [[ ${#windows[@]} -eq 0 ]]; then
  windows_json="[]"
else
  windows_json=$(printf '%s\n' "${windows[@]}" | jq -s '.')
fi

monitors_json=$(jq -c '[.[] | {id, name, width, height}]' <<<"$monitors")

focused_window=$(jq '.address' <<<"$activewindow")
focus_monitors_json=$(jq -c '[.[] | {
  monitor: .name,
  active_workspace: .activeWorkspace.name,
  special_workspace: (if .specialWorkspace.name == "" then null else .specialWorkspace.name end)
}]' <<<"$monitors")
focus_json=$(jq -nc --argjson focused_window "$focused_window" --argjson monitors "$focus_monitors_json" \
  '{focused_window: $focused_window, monitors: $monitors}')

jq -nc \
  --arg captured_at "$captured_at" \
  --argjson monitors "$monitors_json" \
  --argjson focus "$focus_json" \
  --argjson windows "$windows_json" \
  '{version: 1, captured_at: $captured_at, monitors: $monitors, focus: $focus, windows: $windows}'
