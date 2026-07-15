#!/usr/bin/env bash
set -euo pipefail

if [[ ${HYPR_RICE_LIVE_TEST:-} != 1 ]]; then
  printf '%s\n' 'test-hypr-layout-live is destructive to a disposable workspace; rerun with HYPR_RICE_LIVE_TEST=1' >&2
  exit 2
fi

for command in hyprctl hypr-layout ghostty; do
  command -v "$command" >/dev/null || {
    printf 'missing runtime dependency: %s\n' "$command" >&2
    exit 127
  }
done

jqc() {
  nix shell nixpkgs#jq -c jq "$@"
}

run_id="$(printf '%x' "$$")-$RANDOM"
workspace="hypr-rice-live-$run_id"
class="com.mitchellh.ghostty.hypr-rice-live-$run_id"
workspace_selector="name:$workspace"
pids=()
addresses=()
cleaned=false

focused_monitor=$(hyprctl -j monitors)
old_regular=$(printf '%s' "$focused_monitor" | jqc -r '.[] | select(.focused) | .activeWorkspace.name')
old_special=$(printf '%s' "$focused_monitor" | jqc -r '.[] | select(.focused) | .specialWorkspace.name')
if [[ $old_regular =~ ^[0-9]+$ ]]; then
  old_selector=$old_regular
else
  old_selector="name:$old_regular"
fi

recovery_command="hyprctl -j clients | jq -r '.[] | select(.class == \"$class\") | .pid' | xargs -r kill; hyprctl dispatch 'hl.dsp.focus({ workspace = \"$workspace_selector\" })'; hypr-layout reset; hyprctl dispatch 'hl.dsp.focus({ workspace = \"$old_selector\" })'"
printf 'workspace: %s\nclass: %s\nrecovery: %s\n' "$workspace" "$class" "$recovery_command"

focus_workspace() {
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null
}

clients() {
  hyprctl -j clients | jqc --arg class "$class" --arg workspace "$workspace" \
    '[.[] | select(.class == $class and .workspace.name == $workspace)]'
}

cleanup() {
  local status=$?
  [[ $cleaned == true ]] && return "$status"
  cleaned=true
  trap - EXIT INT TERM
  set +e

  if hyprctl -j workspaces | jqc -e --arg workspace "$workspace" \
      'any(.[]; .name == $workspace)' >/dev/null; then
    focus_workspace "$workspace_selector" >/dev/null 2>&1 || true
    hypr-layout reset >/dev/null 2>&1 || true
  fi

  for index in "${!pids[@]}"; do
    pid=${pids[$index]}
    address=${addresses[$index]:-}
    if [[ -n $address ]]; then
      live_pid=$(hyprctl -j clients | jqc -r --arg address "$address" --arg class "$class" \
        '.[] | select(.address == $address and .class == $class) | .pid' 2>/dev/null)
      if [[ $live_pid == "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
      fi
    elif kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  focus_workspace "$old_selector" >/dev/null 2>&1 || true
  if [[ -n $old_special ]]; then
    special_name=${old_special#special:}
    shown=$(hyprctl -j monitors | jqc -r '.[] | select(.focused) | .specialWorkspace.name' 2>/dev/null)
    if [[ $shown != "$old_special" ]]; then
      hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$special_name\")" >/dev/null 2>&1 || true
    fi
  fi

  leftovers=$(hyprctl -j clients | jqc --arg class "$class" '[.[] | select(.class == $class)] | length' 2>/dev/null)
  if [[ ${leftovers:-0} -ne 0 ]]; then
    printf 'cleanup left %s controlled clients; run recovery command:\n%s\n' "$leftovers" "$recovery_command" >&2
    [[ $status -eq 0 ]] && status=1
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_count() {
  local expected=$1 actual=0
  for _ in {1..100}; do
    actual=$(clients | jqc 'length')
    [[ $actual -eq $expected ]] && return 0
    sleep 0.05
  done
  printf 'expected %s controlled clients, observed %s\n' "$expected" "$actual" >&2
  return 1
}

launch_window() {
  local pid address=
  ghostty --class="$class" --confirm-close-surface=false -e sleep infinity >/dev/null 2>&1 &
  pid=$!
  pids+=("$pid")
  for _ in {1..100}; do
    address=$(hyprctl -j clients | jqc -r --argjson pid "$pid" --arg class "$class" \
      '.[] | select(.pid == $pid and .class == $class and .mapped) | .address')
    [[ -n $address ]] && break
    sleep 0.05
  done
  if [[ -z $address ]]; then
    printf 'Ghostty pid %s did not map with class %s\n' "$pid" "$class" >&2
    return 1
  fi
  addresses+=("$address")
  printf '  mapped pid=%s address=%s\n' "$pid" "$address"
}

snapshot_state() {
  printf '%s\n%s\n' \
    "$(hyprctl -j activeworkspace | jqc -S -c '{id,name,tiledLayout,windows}')" \
    "$(hyprctl -j workspacerules | jqc -S -c '.')"
}

expect_rejection() {
  local label=$1 fragment=$2
  shift 2
  local output
  if output=$("$@" 2>&1); then
    printf '%s unexpectedly succeeded: %s\n' "$label" "$output" >&2
    return 1
  fi
  [[ $output == *"$fragment"* ]] || {
    printf '%s returned the wrong error: %s\n' "$label" "$output" >&2
    return 1
  }
  printf '  %s -> %s\n' "$label" "$output"
}

row_geometry_holds() {
  clients | jqc -e '
    sort_by(.at[0]) as $w
    | ($w | length) == 3
      and (([$w[].at[1]] | max) - ([$w[].at[1]] | min) <= 2)
      and (([$w[].size[1]] | max) - ([$w[].size[1]] | min) <= 2)
      and (($w[2].size[0] - $w[0].size[0]) | abs) <= 2
      and ((($w[1].size[0] / $w[0].size[0]) - 2) | abs) <= 0.03
      and ($w[1].at[0] - ($w[0].at[0] + $w[0].size[0])) >= 0
      and ($w[1].at[0] - ($w[0].at[0] + $w[0].size[0])) <= 16
      and ($w[2].at[0] - ($w[1].at[0] + $w[1].size[0])) >= 0
      and ($w[2].at[0] - ($w[1].at[0] + $w[1].size[0])) <= 16
  ' >/dev/null
}

grid_geometry_holds() {
  clients | jqc -e '
    (max_by(.size[1])) as $a
    | (max_by(.size[0])) as $c
    | (.[] | select(.address != $a.address and .address != $c.address)) as $b
    | length == 3
      and (($a.at[1] - $b.at[1]) | abs) <= 2
      and ($a.at[0] < $b.at[0])
      and ($c.at[1] > ($b.at[1] + $b.size[1]))
      and (($c.at[0] - $a.at[0]) | abs) <= 2
      and (($c.size[0] - (($b.at[0] + $b.size[0]) - $a.at[0])) | abs) <= 16
      and (($a.size[1] - (2 * $b.size[1])) | abs) <= 16
      and (($c.at[1] - ($a.at[1] + $a.size[1])) >= 0)
      and (($c.at[1] - ($a.at[1] + $a.size[1])) <= 16)
  ' >/dev/null
}

equal_columns_hold() {
  clients | jqc -e '
    sort_by(.at[0]) as $w
    | ($w | length) == 4
      and (([$w[].at[1]] | max) - ([$w[].at[1]] | min) <= 2)
      and (([$w[].size[1]] | max) - ([$w[].size[1]] | min) <= 2)
      and (([$w[].size[0]] | max) - ([$w[].size[0]] | min) <= 4)
      and all(range(0; 3);
        ($w[. + 1].at[0] - ($w[.].at[0] + $w[.].size[0])) >= 0
        and ($w[. + 1].at[0] - ($w[.].at[0] + $w[.].size[0])) <= 16)
  ' >/dev/null
}

wait_for_geometry() {
  local label=$1 predicate=$2
  for _ in {1..100}; do
    if "$predicate"; then
      printf '  %s geometry: %s\n' "$label" "$(clients | jqc -c 'sort_by(.at[1], .at[0]) | map({address,pid,at,size})')"
      return 0
    fi
    sleep 0.05
  done
  printf '%s geometry did not settle: %s\n' "$label" "$(clients | jqc -c 'map({address,pid,at,size})')" >&2
  return 1
}

printf '%s\n' '=== controlled workspace setup ==='
focus_workspace "$workspace_selector"
for _ in 1 2 3; do launch_window; done
wait_for_count 3

printf '%s\n' '=== invalid inputs preserve native state ==='
before=$(snapshot_state)
expect_rejection malformed 'complete rectangle' hypr-layout 'a a; a b'
printf -v oversized '%4097s' ''
oversized=${oversized// /1}
expect_rejection oversized 'at most 4096 bytes' hypr-layout "$oversized"
expect_rejection injection 'invalid area name' hypr-layout 'x"); error("boom'
expect_rejection arity 'received 3 targets' hypr-layout '1 1'
hyprctl dispatch 'hl.dsp.group.toggle()' >/dev/null
for _ in {1..100}; do
  grouped=$(clients | jqc '[.[].grouped | length] | max // 0')
  [[ $grouped -gt 0 ]] && break
  sleep 0.05
done
expect_rejection grouped 'grouped workspaces are not supported' hypr-layout '1 1 1'
hyprctl dispatch 'hl.dsp.group.toggle()' >/dev/null
for _ in {1..100}; do
  grouped=$(clients | jqc '[.[].grouped | length] | max // 0')
  [[ $grouped -eq 0 ]] && break
  sleep 0.05
done
after=$(snapshot_state)
[[ $before == "$after" ]] || {
  printf 'invalid input mutated workspace state\nbefore:\n%s\nafter:\n%s\n' "$before" "$after" >&2
  exit 1
}
printf '  unchanged: %s\n' "$(hyprctl -j activeworkspace | jqc -c '{name,tiledLayout,windows}')"

printf '%s\n' '=== weighted row 1:2:1 ==='
hypr-layout '1 2 1' >/dev/null
wait_for_geometry 'weighted row' row_geometry_holds
[[ $(hyprctl -j activeworkspace | jqc -r .tiledLayout) == 'lua:rice' ]]

printf '%s\n' '=== area grid with empty cell ==='
hypr-layout 'a b; a .; c c' >/dev/null
wait_for_geometry 'area grid' grid_geometry_holds

printf '%s\n' '=== target drift equal-column fallback ==='
launch_window
wait_for_count 4
wait_for_geometry 'equal-column fallback' equal_columns_hold

printf '%s\n' '=== automatic requested-layout resumption ==='
drift_pid=${pids[3]}
kill "$drift_pid"
wait "$drift_pid" 2>/dev/null || true
wait_for_count 3
wait_for_geometry 'area-grid resumption' grid_geometry_holds

printf '%s\n' '=== LIVE HYPR RICE PASS ==='
