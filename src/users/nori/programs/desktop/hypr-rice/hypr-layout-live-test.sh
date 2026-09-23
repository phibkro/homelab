#!/usr/bin/env bash
set -euo pipefail

if [[ ${HYPR_RICE_LIVE_TEST:-} != 1 ]]; then
  printf '%s\n' 'test-hypr-layout-live is destructive to disposable workspaces; rerun with HYPR_RICE_LIVE_TEST=1' >&2
  exit 2
fi

for command in hyprctl hypr-layout tile-ratio glass-spacer ghostty; do
  command -v "$command" >/dev/null || {
    printf 'missing runtime dependency: %s\n' "$command" >&2
    exit 127
  }
done

if jq_bin=$(command -v jq); then
  jqc() {
    "$jq_bin" "$@"
  }
else
  command -v nix >/dev/null || {
    printf '%s\n' 'missing runtime dependency: jq (and nix fallback is unavailable)' >&2
    exit 127
  }
  jqc() {
    nix shell nixpkgs#jq -c jq "$@"
  }
fi

hex() {
  printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'
}

# Only hexadecimal produced by hex() is interpolated into Lua source. Runtime
# selectors remain data, including named/special workspace names and addresses.
lua_string() {
  printf '(("%s"):gsub("..", function(h) return string.char(tonumber(h, 16)) end))' "$(hex "$1")"
}

run_id="$(printf '%x' "$$")-$RANDOM"
workspace="hypr-rice-live-$run_id"
workspace_selector="name:$workspace"
special_name="hypr-rice-special-$run_id"
special_workspace="special:$special_name"
special_selector="$special_workspace"
class_prefix="com.mitchellh.ghostty.hypr-rice-live-$run_id"
spacer_class=${HYPR_RICE_SPACER_CLASS:?HYPR_RICE_SPACER_CLASS is required}
pids=()
addresses=()
classes=()
labels=()
cleaned=false

focused_monitor=$(hyprctl -j monitors)
old_regular=$(printf '%s' "$focused_monitor" | jqc -r '.[] | select(.focused) | .activeWorkspace.name')
old_special=$(printf '%s' "$focused_monitor" | jqc -r '.[] | select(.focused) | .specialWorkspace.name')
if [[ $old_regular =~ ^[0-9]+$ ]]; then
  old_selector=$old_regular
else
  old_selector="name:$old_regular"
fi

printf 'regular workspace: %s\nspecial workspace: %s\ncontent class prefix: %s\n' \
  "$workspace" "$special_workspace" "$class_prefix"

shown_special() {
  hyprctl -j monitors | jqc -r '.[] | select(.focused) | .specialWorkspace.name'
}

dispatch_focus_workspace() {
  local selector encoded
  selector=$1
  encoded=$(lua_string "$selector")
  hyprctl dispatch "hl.dsp.focus({ workspace = $encoded })" >/dev/null
}

dispatch_focus_window() {
  local address encoded
  address=$1
  encoded=$(lua_string "address:$address")
  hyprctl dispatch "hl.dsp.focus({ window = $encoded })" >/dev/null
}

dispatch_toggle_special() {
  local name encoded
  name=$1
  encoded=$(lua_string "$name")
  hyprctl dispatch "hl.dsp.workspace.toggle_special($encoded)" >/dev/null
}

wait_until() {
  local label=$1
  shift
  for _ in {1..100}; do
    if "$@"; then
      return 0
    fi
    sleep 0.05
  done
  printf 'timed out waiting for %s\n' "$label" >&2
  return 1
}

special_is() {
  [[ $(shown_special) == "$1" ]]
}

regular_workspace_is_active() {
  local workspace_name=$1
  hyprctl -j monitors | jqc -e --arg workspace "$workspace_name" \
    'any(.[]; .focused and .activeWorkspace.name == $workspace and .specialWorkspace.name == "")' >/dev/null
}

workspace_exists() {
  hyprctl -j workspaces | jqc -e --arg workspace "$1" 'any(.[]; .name == $workspace)' >/dev/null
}

workspace_absent() {
  ! workspace_exists "$1"
}

workspace_layout_is() {
  local workspace_name=$1 expected=$2
  hyprctl -j workspaces | jqc -e --arg workspace "$workspace_name" --arg expected "$expected" \
    'any(.[]; .name == $workspace and .tiledLayout == $expected)' >/dev/null
}

address_set_json() {
  jqc -cn --args '$ARGS.positional' "${addresses[@]}"
}

controlled_clients() {
  local address_set
  address_set=$(address_set_json)
  hyprctl -j clients | jqc --argjson addresses "$address_set" \
    '[.[] | select(.address as $address | $addresses | index($address))]'
}

workspace_clients() {
  local workspace_name=$1
  controlled_clients | jqc --arg workspace "$workspace_name" \
    '[.[] | select(.workspace.name == $workspace)]'
}

workspace_tiled_clients() {
  local workspace_name=$1
  workspace_clients "$workspace_name" | jqc '[.[] | select(.mapped and (.floating | not))]'
}

workspace_client_count_is() {
  local workspace_name=$1 expected=$2
  [[ $(workspace_clients "$workspace_name" | jqc 'length') -eq $expected ]]
}

workspace_tiled_count_is() {
  local workspace_name=$1 expected=$2
  [[ $(workspace_tiled_clients "$workspace_name" | jqc 'length') -eq $expected ]]
}

client_floating_is() {
  local address=$1 expected=$2
  hyprctl -j clients | jqc -e --arg address "$address" --argjson expected "$expected" \
    'any(.[]; .address == $address and .floating == $expected)' >/dev/null
}

grouped_count_is() {
  local workspace_name=$1 comparison=$2
  local grouped
  grouped=$(workspace_clients "$workspace_name" | jqc '[.[].grouped | length] | max // 0')
  case $comparison in
    positive) [[ $grouped -gt 0 ]] ;;
    zero) [[ $grouped -eq 0 ]] ;;
    *) return 2 ;;
  esac
}

client_absent() {
  local address=$1
  ! hyprctl -j clients | jqc -e --arg address "$address" 'any(.[]; .address == $address)' >/dev/null
}

client_stable_id() {
  local address=$1
  hyprctl -j clients | jqc -r --arg address "$address" \
    '.[] | select(.address == $address) | .stableId'
}

client_width() {
  local address=$1
  hyprctl -j clients | jqc -r --arg address "$address" \
    '.[] | select(.address == $address) | .size[0]'
}

register_process() {
  pids+=("$1")
  addresses+=("$2")
  classes+=("$3")
  labels+=("$4")
}

launch_client() {
  local label=$1 workspace_name=$2 expected_class=$3 mode=$4
  local pid address=

  if [[ $mode == spacer ]]; then
    glass-spacer >/dev/null 2>&1 &
  else
    ghostty --class="$expected_class" --title="$label" --confirm-close-surface=false \
      -e sleep infinity >/dev/null 2>&1 &
  fi
  pid=$!
  register_process "$pid" "" "$expected_class" "$label"

  for _ in {1..100}; do
    address=$(hyprctl -j clients | jqc -r --argjson pid "$pid" --arg class "$expected_class" --arg workspace "$workspace_name" \
      '.[] | select(.pid == $pid and .class == $class and .workspace.name == $workspace and .mapped) | .address')
    [[ -n $address ]] && break
    sleep 0.05
  done
  if [[ -z $address ]]; then
    printf '%s pid %s did not map as class %s on %s\n' "$label" "$pid" "$expected_class" "$workspace_name" >&2
    return 1
  fi

  addresses[${#addresses[@]} - 1]=$address
  printf '  mapped label=%s pid=%s address=%s class=%s workspace=%s\n' \
    "$label" "$pid" "$address" "$expected_class" "$workspace_name"
  REPLY=$address
}

capture_visual_order() {
  local workspace_name=$1 snapshot
  snapshot=$(workspace_tiled_clients "$workspace_name" | jqc -e '
    map({address, pid, class, stableId, at, size})
    | select(length > 0)
    | select(all(.[];
        (.address | type) == "string" and (.address | length) > 0
        and (.stableId | type) == "string" and (.stableId | test("^[0-9a-f]+$"))
        and (.at | type) == "array" and (.at | length) == 2
        and (.size | type) == "array" and (.size | length) == 2))
    | select((map(.address) | unique | length) == length)
    | select((map(.stableId) | unique | length) == length)
    | sort_by(.at[1], .at[0])
    | select(([group_by([.at[1], .at[0]])[] | select(length > 1)] | length) == 0)
  ') || {
    printf 'could not capture unique address/stableId row-major geometry on %s: %s\n' \
      "$workspace_name" "$(workspace_tiled_clients "$workspace_name" | jqc -c 'map({address,pid,class,stableId,at,size})')" >&2
    return 1
  }
  printf '%s' "$snapshot"
}

capture_addresses() {
  printf '%s' "$1" | jqc -c 'map(.address)'
}

same_address_order() {
  [[ $(capture_addresses "$1") == "$(capture_addresses "$2")" ]]
}

area_mapping_holds() {
  local workspace_name=$1 order=$2
  workspace_tiled_clients "$workspace_name" | jqc -e --argjson order "$order" '
    . as $actual
    | [$order[] | .address as $address | $actual[] | select(.address == $address)] as $w
    | ($w | length) == 4
      and ($w[0].address == $order[0].address)
      and ($w[1].address == $order[1].address)
      and ($w[2].address == $order[2].address)
      and ($w[3].address == $order[3].address)
      and (($w[0].at[1] - $w[1].at[1]) | abs) <= 2
      and ($w[0].at[0] < $w[1].at[0])
      and (($w[1].at[0] - $w[2].at[0]) | abs) <= 2
      and ($w[2].at[1] > ($w[1].at[1] + $w[1].size[1]))
      and (($w[0].at[0] - $w[3].at[0]) | abs) <= 2
      and ($w[3].at[1] > ($w[0].at[1] + $w[0].size[1]))
      and (($w[3].size[0] - (($w[1].at[0] + $w[1].size[0]) - $w[0].at[0])) | abs) <= 16
      and (($w[0].size[1] - (($w[2].at[1] + $w[2].size[1]) - $w[1].at[1])) | abs) <= 16
      and (([$w[1].size[1], $w[2].size[1], $w[3].size[1]] | max)
        - ([$w[1].size[1], $w[2].size[1], $w[3].size[1]] | min) <= 8)
  ' >/dev/null
}

equal_columns_hold() {
  local workspace_name=$1 expected=$2
  workspace_tiled_clients "$workspace_name" | jqc -e --argjson expected "$expected" '
    sort_by(.at[0]) as $w
    | ($w | length) == $expected
      and (([$w[].at[1]] | max) - ([$w[].at[1]] | min) <= 2)
      and (([$w[].size[1]] | max) - ([$w[].size[1]] | min) <= 2)
      and (([$w[].size[0]] | max) - ([$w[].size[0]] | min) <= 4)
      and all(range(0; $expected - 1);
        ($w[. + 1].at[0] - ($w[.].at[0] + $w[.].size[0])) >= 0
        and ($w[. + 1].at[0] - ($w[.].at[0] + $w[.].size[0])) <= 16)
  ' >/dev/null
}

wait_for_area_mapping() {
  local label=$1 workspace_name=$2 order=$3
  for _ in {1..100}; do
    if area_mapping_holds "$workspace_name" "$order"; then
      printf '  %s: %s\n' "$label" \
        "$(workspace_tiled_clients "$workspace_name" | jqc -c 'sort_by(.at[1], .at[0]) | map({address,stableId,at,size})')"
      return 0
    fi
    sleep 0.05
  done
  printf '%s mapping did not settle; expected order=%s actual=%s\n' "$label" "$order" \
    "$(workspace_tiled_clients "$workspace_name" | jqc -c 'map({address,stableId,at,size})')" >&2
  return 1
}

wait_for_equal_columns() {
  local label=$1 workspace_name=$2 expected=$3
  for _ in {1..100}; do
    if equal_columns_hold "$workspace_name" "$expected"; then
      printf '  %s: %s\n' "$label" \
        "$(workspace_tiled_clients "$workspace_name" | jqc -c 'sort_by(.at[0]) | map({address,stableId,at,size})')"
      return 0
    fi
    sleep 0.05
  done
  printf '%s equal-column fallback did not settle: %s\n' "$label" \
    "$(workspace_tiled_clients "$workspace_name" | jqc -c 'map({address,stableId,at,size})')" >&2
  return 1
}

snapshot_state() {
  printf '%s\n%s\n' \
    "$(hyprctl -j activeworkspace | jqc -S -c '{id,name,tiledLayout,windows}')" \
    "$(hyprctl -j workspacerules | jqc -S -c '.')"
}

snapshot_geometry_rules() {
  local workspace_name=$1 selector=$2
  printf '%s\n%s\n%s\n' \
    "$(workspace_clients "$workspace_name" | jqc -S -c 'sort_by(.address) | map({address,stableId,at,size,floating})')" \
    "$(hyprctl -j workspaces | jqc -S -c --arg workspace "$workspace_name" '.[] | select(.name == $workspace) | {id,name,tiledLayout,windows}')" \
    "$(hyprctl -j workspacerules | jqc -S -c --arg selector "$selector" '[.[] | select(.workspaceString == $selector)]')"
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

cleanup() {
  local status=$? shown special_short index pid address expected_class live_pid leftovers errors rules_left
  [[ $cleaned == true ]] && return "$status"
  cleaned=true
  trap - EXIT INT TERM
  set +e

  if workspace_exists "$special_workspace"; then
    shown=$(shown_special 2>/dev/null)
    if [[ $shown != "$special_workspace" ]]; then
      if ! dispatch_toggle_special "$special_name" >/dev/null 2>&1 \
          || ! wait_until 'disposable special workspace visibility for reset' special_is "$special_workspace" >/dev/null 2>&1; then
        printf '%s\n' 'cleanup could not make the disposable special workspace visible; refusing to reset another workspace' >&2
        status=1
      fi
    fi
    shown=$(shown_special 2>/dev/null)
    if [[ $shown == "$special_workspace" ]]; then
      hypr-layout reset >/dev/null 2>&1 || status=1
      dispatch_toggle_special "$special_name" >/dev/null 2>&1 || status=1
      wait_until 'disposable special workspace hidden during cleanup' special_is '' >/dev/null 2>&1 || status=1
    fi
  fi

  shown=$(shown_special 2>/dev/null)
  if [[ -n $shown ]]; then
    special_short=${shown#special:}
    dispatch_toggle_special "$special_short" >/dev/null 2>&1
    wait_until 'all special workspaces hidden during cleanup' special_is '' >/dev/null 2>&1
  fi

  if workspace_exists "$workspace"; then
    if dispatch_focus_workspace "$workspace_selector" >/dev/null 2>&1 \
        && wait_until 'disposable regular workspace focus for reset' regular_workspace_is_active "$workspace" >/dev/null 2>&1; then
      hypr-layout reset >/dev/null 2>&1 || status=1
    else
      printf '%s\n' 'cleanup could not focus the disposable regular workspace; refusing to reset another workspace' >&2
      status=1
    fi
  fi

  for index in "${!pids[@]}"; do
    pid=${pids[$index]}
    address=${addresses[$index]:-}
    expected_class=${classes[$index]}
    if [[ -n $address ]]; then
      live_pid=$(hyprctl -j clients | jqc -r --arg address "$address" --arg class "$expected_class" \
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

  wait_until 'disposable regular workspace removal' workspace_absent "$workspace" >/dev/null 2>&1 || status=1
  wait_until 'disposable special workspace removal' workspace_absent "$special_workspace" >/dev/null 2>&1 || status=1

  dispatch_focus_workspace "$old_selector" >/dev/null 2>&1 || status=1
  shown=$(shown_special 2>/dev/null)
  if [[ -n $shown ]]; then
    special_short=${shown#special:}
    dispatch_toggle_special "$special_short" >/dev/null 2>&1
    wait_until 'special workspace hidden before restoration' special_is '' >/dev/null 2>&1 || status=1
  fi
  if [[ -n $old_special ]]; then
    special_short=${old_special#special:}
    dispatch_toggle_special "$special_short" >/dev/null 2>&1
    wait_until 'prior special workspace restoration' special_is "$old_special" >/dev/null 2>&1 || status=1
  fi

  hyprctl reload >/dev/null 2>&1 || status=1
  errors=$(hyprctl configerrors 2>/dev/null)
  if [[ -n $errors ]]; then
    printf 'Hyprland config errors after cleanup reload:\n%s\n' "$errors" >&2
    status=1
  fi

  rules_left=$(hyprctl -j workspacerules | jqc -r --arg regular "$workspace_selector" --arg special "$special_selector" \
    '[.[] | select(.workspaceString == $regular or .workspaceString == $special)] | length' 2>/dev/null)
  if [[ ${rules_left:-1} -ne 0 ]]; then
    printf 'cleanup left disposable workspace rules: %s\n' \
      "$(hyprctl -j workspacerules | jqc -c --arg regular "$workspace_selector" --arg special "$special_selector" '[.[] | select(.workspaceString == $regular or .workspaceString == $special)]' 2>/dev/null)" >&2
    status=1
  fi

  leftovers=$(controlled_clients | jqc 'length' 2>/dev/null)
  if [[ ${leftovers:-1} -ne 0 ]]; then
    printf 'cleanup left controlled clients: %s\n' \
      "$(controlled_clients | jqc -c 'map({address,pid,class,workspace})' 2>/dev/null)" >&2
    printf 'exact recorded processes: %s\n' "${pids[*]}" >&2
    status=1
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' '=== controlled workspace setup ==='
if [[ -n $old_special ]]; then
  dispatch_toggle_special "${old_special#special:}"
  wait_until 'prior special workspace hidden for isolation' special_is ''
fi
dispatch_focus_workspace "$workspace_selector"
for index in 1 2 3; do
  launch_client "content-$index" "$workspace" "$class_prefix.content-$index" content
  printf -v "content_${index}_address" '%s' "$REPLY"
done
launch_client 'glass-spacer' "$workspace" "$spacer_class" spacer
wait_until 'four controlled regular clients' workspace_client_count_is "$workspace" 4

printf '%s\n' '=== capture address, opaque stableId, and row-major geometry ==='
initial_capture=$(capture_visual_order "$workspace")
[[ $(printf '%s' "$initial_capture" | jqc 'length') -eq 4 ]]
printf '  captured: %s\n' "$(printf '%s' "$initial_capture" | jqc -c '.')"

printf '%s\n' '=== invalid inputs preserve native state ==='
before=$(snapshot_state)
expect_rejection malformed 'complete rectangle' hypr-layout 'a a; a b'
printf -v oversized '%4097s' ''
oversized=${oversized// /1}
expect_rejection oversized 'at most 4096 bytes' hypr-layout "$oversized"
expect_rejection injection 'invalid area name' hypr-layout 'x"); error("boom'
expect_rejection dot-cell 'invalid area name' hypr-layout 'a b; a .; c c'
expect_rejection arity 'received 4 targets' hypr-layout '1 1 1'
dispatch_focus_window "$(printf '%s' "$initial_capture" | jqc -r '.[0].address')"
hyprctl dispatch 'hl.dsp.group.toggle()' >/dev/null
wait_until 'controlled group creation' grouped_count_is "$workspace" positive
expect_rejection grouped 'grouped workspaces are not supported' hypr-layout '1 1 1 1'
hyprctl dispatch 'hl.dsp.group.toggle()' >/dev/null
wait_until 'controlled group removal' grouped_count_is "$workspace" zero
after=$(snapshot_state)
[[ $before == "$after" ]] || {
  printf 'invalid input mutated workspace state\nbefore:\n%s\nafter:\n%s\n' "$before" "$after" >&2
  exit 1
}

printf '%s\n' '=== four-target area mapping by captured identity ==='
hypr-layout 'a b; a d; c c' >/dev/null
wait_until 'regular workspace rice layout' workspace_layout_is "$workspace" 'lua:rice'
wait_for_area_mapping 'initial identity mapping' "$workspace" "$initial_capture"

printf '%s\n' '=== same client float fallback and stable-ID resumption ==='
float_address=$(printf '%s' "$initial_capture" | jqc -r '.[1].address')
float_stable_id=$(printf '%s' "$initial_capture" | jqc -r '.[1].stableId')
dispatch_focus_window "$float_address"
hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })' >/dev/null
wait_until 'captured client floating' client_floating_is "$float_address" true
wait_until 'three tiled targets while floating' workspace_tiled_count_is "$workspace" 3
wait_for_equal_columns 'floating target fallback' "$workspace" 3
[[ $(client_stable_id "$float_address") == "$float_stable_id" ]]
dispatch_focus_window "$float_address"
hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })' >/dev/null
wait_until 'captured client tiled again' client_floating_is "$float_address" false
wait_until 'four tiled targets after refloat' workspace_tiled_count_is "$workspace" 4
[[ $(client_stable_id "$float_address") == "$float_stable_id" ]]
wait_for_area_mapping 'stable-ID mapping resumed' "$workspace" "$initial_capture"

printf '%s\n' '=== reset, deterministic native reorder, and explicit recapture ==='
hypr-layout reset >/dev/null
wait_until 'regular workspace reset to dwindle' workspace_layout_is "$workspace" dwindle
native_before=$(capture_visual_order "$workspace")
swap_address=$(printf '%s' "$native_before" | jqc -r '.[0].address')
dispatch_focus_window "$swap_address"
if ! swap_output=$(hyprctl dispatch 'hl.dsp.window.swap({ direction = "right" })' 2>&1); then
  printf 'deterministic native-order dispatcher failed: %s\n' "$swap_output" >&2
  exit 1
fi
native_after=
for _ in {1..100}; do
  native_after=$(capture_visual_order "$workspace")
  if ! same_address_order "$native_before" "$native_after"; then
    break
  fi
  sleep 0.05
done
if [[ -z $native_after ]] || same_address_order "$native_before" "$native_after"; then
  printf 'hl.dsp.window.swap({ direction = "right" }) did not alter row-major native order; refusing to fake recapture coverage\n' >&2
  exit 1
fi
printf '  native order before: %s\n  native order after:  %s\n' \
  "$(capture_addresses "$native_before")" "$(capture_addresses "$native_after")"
hypr-layout 'a b; a d; c c' >/dev/null
wait_for_area_mapping 'explicit reapply recaptured native order' "$workspace" "$native_after"

printf '%s\n' '=== killed known target and deterministic replacement append ==='
kill_entry=$(printf '%s' "$native_after" | jqc -c --arg spacer "$spacer_class" '[.[] | select(.class != $spacer)][0]')
kill_address=$(printf '%s' "$kill_entry" | jqc -r '.address')
kill_pid=$(printf '%s' "$kill_entry" | jqc -r '.pid')
kill_stable_id=$(printf '%s' "$kill_entry" | jqc -r '.stableId')
kill "$kill_pid"
wait "$kill_pid" 2>/dev/null || true
wait_until 'captured content target removal' client_absent "$kill_address"
wait_until 'three known tiled targets after kill' workspace_tiled_count_is "$workspace" 3
wait_for_equal_columns 'killed target fallback' "$workspace" 3
launch_client 'replacement' "$workspace" "$class_prefix.replacement" content
replacement_address=$REPLY
wait_until 'replacement restores four regular targets' workspace_tiled_count_is "$workspace" 4
replacement_stable_id=$(client_stable_id "$replacement_address")
printf '%s' "$native_after" | jqc -e --arg stableId "$replacement_stable_id" \
  'all(.[]; .stableId != $stableId)' >/dev/null
[[ $replacement_stable_id != "$kill_stable_id" ]]
replacement_order=$(printf '%s' "$native_after" | jqc -c --arg killed "$kill_address" --arg replacement "$replacement_address" \
  '[.[] | select(.address != $killed)] + [{address: $replacement}]')
wait_for_area_mapping 'surviving known ranks then unknown append' "$workspace" "$replacement_order"

printf '%s\n' '=== visible special workspace wins over underlying regular focus ==='
regular_layout_before_special=$(hyprctl -j workspaces | jqc -r --arg workspace "$workspace" '.[] | select(.name == $workspace) | .tiledLayout')
dispatch_focus_window "$replacement_address"
underlying_active=$(hyprctl -j activewindow | jqc -r '.workspace.name')
[[ $underlying_active == "$workspace" ]]
dispatch_toggle_special "$special_name"
wait_until 'disposable special workspace visible' special_is "$special_workspace"
[[ $(hyprctl -j activewindow | jqc -r '.workspace.name') == "$workspace" ]] || {
  printf '%s\n' 'underlying regular window did not remain active before the special received a client' >&2
  exit 1
}
empty_special_before=$(snapshot_geometry_rules "$workspace" "$workspace_selector")
expect_rejection empty-special-arity 'received 0 targets' hypr-layout '1 1 1 1'
empty_special_after=$(snapshot_geometry_rules "$workspace" "$workspace_selector")
[[ $empty_special_before == "$empty_special_after" ]] || {
  printf '%s\n' 'empty special apply mutated the underlying regular workspace' >&2
  exit 1
}
launch_client 'special-1' "$special_workspace" "$class_prefix.special-1" content
launch_client 'special-2' "$special_workspace" "$class_prefix.special-2" content
wait_until 'two controlled special clients' workspace_client_count_is "$special_workspace" 2
hypr-layout '1 1' >/dev/null
wait_until 'visible special workspace rice layout' workspace_layout_is "$special_workspace" 'lua:rice'
[[ $(hyprctl -j workspaces | jqc -r --arg workspace "$workspace" '.[] | select(.name == $workspace) | .tiledLayout') == "$regular_layout_before_special" ]]
hypr-layout reset >/dev/null
wait_until 'visible special workspace reset to dwindle' workspace_layout_is "$special_workspace" dwindle
[[ $(hyprctl -j workspaces | jqc -r --arg workspace "$workspace" '.[] | select(.name == $workspace) | .tiledLayout') == "$regular_layout_before_special" ]]
dispatch_toggle_special "$special_name"
wait_until 'disposable special workspace hidden after targeting test' special_is ''

printf '%s\n' '=== direct absolute tile-ratio spellings on Dwindle ==='
dispatch_focus_workspace "$workspace_selector"
hypr-layout reset >/dev/null
wait_until 'ratio workspace uses dwindle' workspace_layout_is "$workspace" dwindle
ratio_address=$replacement_address
ratio_widths=()
for ratio in '2/5' '0.4' '40%'; do
  dispatch_focus_window "$ratio_address"
  tile-ratio "$ratio" >/dev/null
  [[ $(hyprctl -j activewindow | jqc -r '.address') == "$ratio_address" ]]
  ratio_widths+=("$(client_width "$ratio_address")")
  printf '  ratio=%s focused-width=%s\n' "$ratio" "${ratio_widths[-1]}"
done
printf '%s\n' "${ratio_widths[@]}" | jqc -Rse '
  split("\n")[:-1] | map(tonumber)
  | (max - min) < 3
' >/dev/null || {
  printf 'equivalent ratio spellings differed by >=3px: %s\n' "${ratio_widths[*]}" >&2
  exit 1
}

printf '%s\n' '=== tile-ratio lua:rice guard preserves geometry and rules ==='
guard_capture=$(capture_visual_order "$workspace")
hypr-layout 'a b; a d; c c' >/dev/null
wait_for_area_mapping 'guard baseline rice mapping' "$workspace" "$guard_capture"
dispatch_focus_window "$ratio_address"
guard_before=$(snapshot_geometry_rules "$workspace" "$workspace_selector")
expect_rejection rice-guard 'run "hypr-layout reset"' tile-ratio '2/5'
guard_after=$(snapshot_geometry_rules "$workspace" "$workspace_selector")
[[ $guard_before == "$guard_after" ]] || {
  printf 'tile-ratio rice guard mutated geometry or rules\nbefore:\n%s\nafter:\n%s\n' "$guard_before" "$guard_after" >&2
  exit 1
}

printf '%s\n' '=== LIVE HYPR RICE PASS ==='
