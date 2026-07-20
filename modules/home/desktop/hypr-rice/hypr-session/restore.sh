#!/usr/bin/env bash
# Restore engine: replays a captured snapshot (schema v1) back into
# Hyprland. Best-effort, loud about gaps — see
# docs/specs/2026-07-20-hypr-session-persistence-design.md § Restore
# engine + adapters. This is REPLAY, not attach: every window is a fresh
# process (see spec's Herdr § "attach vs replay"), so matching a resurrected
# window back to its captured record is inherently heuristic — every
# heuristic used below is named in the comment at its call site.
#
# Usage: restore.sh [NAME] [--diff] [--json]
#   NAME     restore named/<NAME>.json instead of current.json
#   --diff   print what WOULD be dispatched; dispatch nothing
#   --json   print the restore report as JSON (default: human-readable)
#
# All hyprctl dispatch calls use the lua builder form (this homelab moved
# off hyprlang — see .claude/skills/gotcha-hyprland-lua-migration). Two
# idioms are LIVE-VERIFIED (2026-07-20, Hyprland 0.55):
#   spawn into a workspace:  hl.dsp.exec_cmd("CMD", { workspace = "W" })
#   move by address:         hl.dsp.window.move({ workspace = "W",
#                               silent = true, window = "address:0x.." })
# toggle_special is confirmed to require the positional-string form —
# the `{ name = "X" }` table form silently no-ops.
# Floating-geometry reapply is split into two independently-tracked
# dispatches — position and size — because they are NOT equally trusted:
#   position (hl.dsp.window.move with x/y/exact)   VERIFIED live-in-VM
#     2026-07-20 (Hyprland 0.55.4, e2e-hypr-session): seed move to
#     (100,80) landed and restore's reapply reproduced it.
#   size (hl.dsp.window.resize with width/height/exact) CONFIRMED BROKEN
#     same run: dispatched 500x300 twice, window stayed at the
#     700x500 rule-default both times — a silent no-op, not an error.
#     The correct 0.55 lua-builder grammar for pixel-exact resize is
#     still unknown (this repo has no live Hyprland session reachable
#     from a test sandbox to iterate against, and mutating the
#     operator's own session is off-limits — see task constraints).
#     Dispatched anyway as best-effort (matches design's "best-effort
#     restore" value; a no-op dispatch is harmless) but the report NEVER
#     claims it worked — see report_restored call sites below, action
#     "size" always says "best-effort". Whoever tracks this down next:
#     confirm via `just test-hypr-session-e2e`, don't guess-and-merge.
#
# Requires on PATH: hyprctl, jq, bash (assoc arrays + namerefs, 4.3+),
# coreutils (sleep). Nix wrapping closes over these; login PATH is thin.
#
# Env:
#   HYPRLAND_INSTANCE_SIGNATURE       which compositor instance hyprctl
#                                      targets — passed through untouched.
#   HYPR_SESSION_STATE_DIR            snapshot store root (default
#                                      ~/.local/state/hypr-session).
#   HYPR_SESSION_RESTORE_MAX_POLLS    poll attempts waiting for a
#                                      launch-once app's windows to appear
#                                      (default 20).
#   HYPR_SESSION_RESTORE_POLL_INTERVAL  sleep between polls, seconds,
#                                      fractional OK (default 0.5).
set -euo pipefail

die() {
  printf 'restore.sh: %s\n' "$1" >&2
  exit 1
}

# ---- arg parsing -----------------------------------------------------
diff_mode=false
json_out=false
name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --diff)
    diff_mode=true
    shift
    ;;
  --json)
    json_out=true
    shift
    ;;
  -*)
    die "unknown flag: $1"
    ;;
  *)
    name=$1
    shift
    ;;
  esac
done

# hyprctl is only needed once we're about to actually dispatch — --diff
# never touches it. Checked before jq so a fully-empty PATH surfaces the
# dispatch-blocking gap first (the one that matters for a real restore).
$diff_mode || command -v hyprctl >/dev/null 2>&1 || die "hyprctl not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

# ---- resolve + validate snapshot -------------------------------------
state_dir=$(hypr_session_state_dir)
if [[ -n $name ]]; then
  snapshot_path="$state_dir/named/$name.json"
else
  snapshot_path="$state_dir/current.json"
fi
[[ -f $snapshot_path ]] || die "no snapshot found at $snapshot_path"

snapshot=$(cat "$snapshot_path")
version=$(jq -r '.version' <<<"$snapshot")
[[ $version == "1" ]] || die "unsupported snapshot schema version: $version (restore.sh only understands version 1)"

max_polls=${HYPR_SESSION_RESTORE_MAX_POLLS:-20}
poll_interval=${HYPR_SESSION_RESTORE_POLL_INTERVAL:-0.5}

# ---- lua dispatch builders --------------------------------------------
# One place for the string-escaping every dispatch call needs: embed as a
# double-quoted lua string literal (backslash then quote, in that order).
lua_str() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

dispatch() {
  hyprctl dispatch "$1" >/dev/null
}

# Verified idiom: hl.dsp.exec_cmd("CMD", { workspace = "W" }). A special
# workspace target carries the "silent" modifier INSIDE the workspace
# string (verified shape); plain workspaces don't — that combination
# isn't live-verified and a spurious flicker is the acceptable fallback
# over guessing dispatcher grammar.
dispatch_spawn() {
  local cmd=$1 workspace=$2
  local ws_arg=$workspace
  [[ $workspace == special:* ]] && ws_arg="$workspace silent"
  if [[ -n $workspace ]]; then
    dispatch "hl.dsp.exec_cmd($(lua_str "$cmd"), { workspace = $(lua_str "$ws_arg") })"
  else
    dispatch "hl.dsp.exec_cmd($(lua_str "$cmd"))"
  fi
}

# Verified idiom: hl.dsp.window.move({ workspace = "W", silent = true,
# window = "address:0x.." }).
dispatch_move_to_workspace() {
  local address=$1 workspace=$2
  dispatch "hl.dsp.window.move({ workspace = $(lua_str "$workspace"), silent = true, window = $(lua_str "address:$address") })"
}

# VERIFIED (see header) — position half of floating-geometry reapply.
dispatch_reapply_position() {
  local address=$1 x=$2 y=$3
  dispatch "hl.dsp.window.move({ window = $(lua_str "address:$address"), x = $x, y = $y, exact = true })"
}

# CONFIRMED BROKEN (see header) — dispatched as best-effort anyway;
# never reported as a success. Kept separate from position so a caller
# can tell the two apart in the restore report.
dispatch_reapply_size() {
  local address=$1 width=$2 height=$3
  dispatch "hl.dsp.window.resize({ window = $(lua_str "address:$address"), width = $width, height = $height, exact = true })"
}

# Positional-string form only — the `{ name = "X" }` table form is a
# known no-op (gotcha-hyprland-lua-migration).
dispatch_toggle_special() {
  dispatch "hl.dsp.workspace.toggle_special($(lua_str "$1"))"
}

dispatch_focus_window() {
  dispatch "hl.dsp.focus({ window = $(lua_str "address:$1") })"
}

# ---- respawn command builders -----------------------------------------
# jq's @sh shell-quotes a string, or space-joins a shell-quoted array —
# exactly the token stream `exec` wants.
respawn_cmd_default() {
  local process_json=$1
  printf 'exec %s' "$(jq -r '.cmdline | @sh' <<<"$process_json")"
}

# ghostty's cwd isn't in argv (the terminal inherits it, capture.sh reads
# it from /proc separately) — cd into it explicitly before exec'ing the
# recorded cmdline.
respawn_cmd_ghostty() {
  local process_json=$1
  local cwd cwd_sh cmdline_sh
  cwd=$(jq -r '.cwd' <<<"$process_json")
  cwd_sh=$(jq -rn --arg c "$cwd" '$c | @sh')
  cmdline_sh=$(jq -r '.cmdline | @sh' <<<"$process_json")
  printf 'cd %s && exec %s' "$cwd_sh" "$cmdline_sh"
}

# Launch-once apps (code, zen-beta): respawn bare argv[0] only, dropping
# any recorded folder/file args, so the app's OWN session/hot-exit
# restore drives what reopens rather than us reopening one specific
# instance on top of it.
respawn_cmd_bare() {
  local process_json=$1
  printf 'exec %s' "$(jq -rn --arg a0 "$(jq -r '.cmdline[0]' <<<"$process_json")" '$a0 | @sh')"
}

# ---- identity (live side) --------------------------------------------
# Same heuristic as capture.sh's compute_identity for class "code" (first
# argv[1:] entry that is an existing directory) so a captured
# identity.value can be matched against a resurrected window's live
# cmdline. Routed through lib.sh's adapter_first_existing_arg — the ONE
# place that scan lives, shared with capture.sh's editor/media adapters.
live_identity_code() {
  local pid=$1
  [[ -r /proc/$pid/cmdline ]] || return 1
  local cmdline_json
  cmdline_json=$(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null |
    jq -R -s 'split("\n") | map(select(length > 0))') || return 1
  adapter_first_existing_arg -d "$cmdline_json"
}

# ---- report accumulators ----------------------------------------------
restored_items=()
unrestorable_items=()

report_restored() { # address class workspace action detail
  restored_items+=("$(jq -nc --arg address "$1" --arg class "$2" --arg workspace "$3" --arg action "$4" --arg detail "$5" \
    '{address: $address, class: $class, workspace: $workspace, action: $action, detail: $detail}')")
}

report_unrestorable() { # address class workspace reason
  unrestorable_items+=("$(jq -nc --arg address "$1" --arg class "$2" --arg workspace "$3" --arg reason "$4" \
    '{address: $address, class: $class, workspace: $workspace, reason: $reason}')")
}

to_json_array() {
  local -n ref=$1
  if [[ ${#ref[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${ref[@]}" | jq -s '.'
  fi
}

windows_json=$(jq -c '.windows' <<<"$snapshot")
focused_window_addr=$(jq -r '.focus.focused_window' <<<"$snapshot")

# launch_once_classes: unique classes in first-seen order.
launch_once_classes=()
declare -A seen_launch_once

# pending: records needing a post-respawn live-address resolution —
# floating (geometry reapply), launch-once (move to captured layer), or
# the captured focused window (final focus). Keyed by array index into
# pending_win[] holding the raw window JSON.
pending_win=()

while IFS= read -r win; do
  IFS=$'\t' read -r class address workspace floating < <(
    jq -r '[.class, .address, .workspace, .floating] | @tsv' <<<"$win"
  )
  process=$(jq -c '.process' <<<"$win")

  if adapter_is_launch_once "$class"; then
    if [[ $process == "null" ]]; then
      report_unrestorable "$address" "$class" "$workspace" "no process data captured (pid was dead at capture time)"
      continue
    fi
    if [[ -z ${seen_launch_once[$class]+set} ]]; then
      seen_launch_once[$class]=1
      launch_once_classes+=("$class")
    fi
    pending_win+=("$win")
    continue
  fi

  # default / ghostty adapter: respawn unconditionally into the recorded
  # workspace, right now — we already know exactly where it's going.
  if [[ $process == "null" ]]; then
    report_unrestorable "$address" "$class" "$workspace" "no process data captured (pid was dead at capture time)"
    continue
  fi

  if adapter_is_ghostty "$class"; then
    cmd=$(respawn_cmd_ghostty "$process")
  else
    cmd=$(respawn_cmd_default "$process")
  fi

  if $diff_mode; then
    report_restored "$address" "$class" "$workspace" "spawn" "$cmd"
  else
    dispatch_spawn "$cmd" "$workspace"
    report_restored "$address" "$class" "$workspace" "spawn" "$cmd"
  fi

  if [[ $floating == "true" || $address == "$focused_window_addr" ]]; then
    pending_win+=("$win")
  fi
done < <(jq -c '.[]' <<<"$windows_json")

# ---- launch-once: bare spawn, once per class --------------------------
for class in "${launch_once_classes[@]}"; do
  representative=$(jq -c --arg c "$class" '.[] | select(.class == $c)' <<<"$windows_json" | head -n1)
  process=$(jq -c '.process' <<<"$representative")
  cmd=$(respawn_cmd_bare "$process")
  if $diff_mode; then
    report_restored "" "$class" "" "launch-once" "$cmd"
  else
    dispatch_spawn "$cmd" ""
    report_restored "" "$class" "" "launch-once" "$cmd"
  fi
done

# ---- reconciliation: match pending records to live windows ------------
# claimed[<new address>]=1 prevents double-claiming a live window across
# two captured records that both target the same class/workspace bucket.
declare -A claimed
declare -A resolved # <captured address> -> <new live address>

if ((${#pending_win[@]} > 0)) && ! $diff_mode; then
  attempt_match() {
    local live_json=$1
    # Decoded ONCE per poll and shared across every pending window below
    # — previously each pending window re-decoded the whole live client
    # list independently (O(P) decodes/poll instead of O(1)).
    local -a live_lines live_lines_sorted
    mapfile -t live_lines < <(jq -c '.[]' <<<"$live_json")
    mapfile -t live_lines_sorted < <(printf '%s\n' "${live_lines[@]}" | sort)

    for i in "${!pending_win[@]}"; do
      win=${pending_win[$i]}
      IFS=$'\t' read -r class address workspace < <(
        jq -r '[.class, .address, .workspace] | @tsv' <<<"$win"
      )
      [[ -n ${resolved[$address]+set} ]] && continue
      identity_value=$(jq -r '.identity.value // ""' <<<"$win")

      if adapter_is_launch_once "$class"; then
        case "$(adapter_match_strategy "$class")" in
        identity)
          # Match by identity (e.g. project folder) — never title regex.
          for live in "${live_lines[@]}"; do
            live_addr=$(jq -r '.address' <<<"$live")
            [[ -n ${claimed[$live_addr]+set} ]] && continue
            [[ $(jq -r '.class' <<<"$live") == "$class" ]] || continue
            pid=$(jq -r '.pid' <<<"$live")
            live_id=$(live_identity_code "$pid") || continue
            if [[ -n $identity_value && $live_id == "$identity_value" ]]; then
              resolved[$address]=$live_addr
              claimed[$live_addr]=1
              break
            fi
          done
          ;;
        positional)
          # No identity for this class — best-effort positional match:
          # address order on both sides.
          for live in "${live_lines_sorted[@]}"; do
            live_addr=$(jq -r '.address' <<<"$live")
            [[ -n ${claimed[$live_addr]+set} ]] && continue
            [[ $(jq -r '.class' <<<"$live") == "$class" ]] || continue
            resolved[$address]=$live_addr
            claimed[$live_addr]=1
            break
          done
          ;;
        esac
      else
        # default/ghostty pending record (floating or the focused
        # window): we spawned it into a known workspace, so match on
        # (class, workspace) + order.
        for live in "${live_lines[@]}"; do
          live_addr=$(jq -r '.address' <<<"$live")
          [[ -n ${claimed[$live_addr]+set} ]] && continue
          [[ $(jq -r '.class' <<<"$live") == "$class" ]] || continue
          [[ $(jq -r '.workspace.name' <<<"$live") == "$workspace" ]] || continue
          resolved[$address]=$live_addr
          claimed[$live_addr]=1
          break
        done
      fi
    done
  }

  poll=0
  while ((poll < max_polls)); do
    live_clients=$(hyprctl clients -j)
    attempt_match "$live_clients"

    all_resolved=true
    for win in "${pending_win[@]}"; do
      addr=$(jq -r '.address' <<<"$win")
      [[ -n ${resolved[$addr]+set} ]] || {
        all_resolved=false
        break
      }
    done
    $all_resolved && break

    poll=$((poll + 1))
    ((poll < max_polls)) && sleep "$poll_interval"
  done
fi

# ---- apply post-spawn actions on resolved records ----------------------
for win in "${pending_win[@]}"; do
  IFS=$'\t' read -r address class workspace floating < <(
    jq -r '[.address, .class, .workspace, .floating] | @tsv' <<<"$win"
  )
  geometry=$(jq -c '.geometry' <<<"$win")

  # --diff never runs the reconciliation poll above (nothing was
  # actually dispatched to match against), so falling through to the
  # live-resolution branches below would report "not found"/"could not
  # be re-matched" for records we deliberately never attempted to
  # resolve — a fabricated gap, not an observed one. Report intent only.
  if $diff_mode; then
    if adapter_is_launch_once "$class"; then
      report_restored "$address" "$class" "$workspace" "move" "would move matched window -> $workspace"
    fi
    if [[ $floating == "true" && $geometry != "null" ]]; then
      x=$(jq -r '.x' <<<"$geometry")
      y=$(jq -r '.y' <<<"$geometry")
      width=$(jq -r '.width' <<<"$geometry")
      height=$(jq -r '.height' <<<"$geometry")
      report_restored "$address" "$class" "$workspace" "position" "would reapply $x,$y (verified dispatch)"
      report_restored "$address" "$class" "$workspace" "size" "would attempt ${width}x${height} (best-effort — see restore.sh header)"
    fi
    if [[ $address == "$focused_window_addr" ]]; then
      report_restored "$address" "$class" "$workspace" "focus" "would focus after respawn"
    fi
    continue
  fi

  new_addr=${resolved[$address]-}

  if [[ -z $new_addr ]]; then
    if adapter_is_launch_once "$class"; then
      report_unrestorable "$address" "$class" "$workspace" "app launched once but this window did not appear/match within timeout ($max_polls x ${poll_interval}s)"
    elif [[ $address == "$focused_window_addr" ]]; then
      report_unrestorable "$address" "$class" "$workspace" "respawned but could not be re-matched afterward; captured focus not restored"
    else
      report_unrestorable "$address" "$class" "$workspace" "floating geometry could not be reapplied: window not found after respawn"
    fi
    continue
  fi

  if adapter_is_launch_once "$class"; then
    dispatch_move_to_workspace "$new_addr" "$workspace"
    report_restored "$address" "$class" "$workspace" "move" "moved $new_addr -> $workspace"
  fi

  if [[ $floating == "true" && $geometry != "null" ]]; then
    x=$(jq -r '.x' <<<"$geometry")
    y=$(jq -r '.y' <<<"$geometry")
    width=$(jq -r '.width' <<<"$geometry")
    height=$(jq -r '.height' <<<"$geometry")
    dispatch_reapply_position "$new_addr" "$x" "$y"
    report_restored "$address" "$class" "$workspace" "position" "reapplied $x,$y to $new_addr (verified)"
    dispatch_reapply_size "$new_addr" "$width" "$height"
    report_restored "$address" "$class" "$workspace" "size" "attempted ${width}x${height} on $new_addr (best-effort — 0.55 resizewindowpixel grammar unresolved, may not take effect; see restore.sh header)"
  fi
done

# ---- finalize: show captured specials, focus captured window ----------
if ! $diff_mode; then
  while IFS= read -r special; do
    [[ -n $special && $special != "null" ]] && dispatch_toggle_special "$special"
  done < <(jq -r '.focus.monitors[].special_workspace' <<<"$snapshot" | sort -u)

  if [[ $focused_window_addr != "null" ]]; then
    focus_new_addr=${resolved[$focused_window_addr]-}
    [[ -n $focus_new_addr ]] && dispatch_focus_window "$focus_new_addr"
  fi
fi

# ---- report -------------------------------------------------------------
restored_json=$(to_json_array restored_items)
unrestorable_json=$(to_json_array unrestorable_items)

report=$(jq -nc \
  --argjson diff "$diff_mode" \
  --argjson restored "$restored_json" \
  --argjson unrestorable "$unrestorable_json" \
  '{
    diff: $diff,
    restored: $restored,
    skipped_already_present: {
      windows: [],
      note: "not implemented in v1 - restore never checks for an already-open matching window before respawning; see design DoD backlog"
    },
    unrestorable: $unrestorable
  }')

if $json_out; then
  printf '%s\n' "$report"
else
  restored_count=$(jq '.restored | length' <<<"$report")
  unrestorable_count=$(jq '.unrestorable | length' <<<"$report")
  if $diff_mode; then
    printf 'restore --diff: would act on %s window(s); %s unrestorable\n' "$restored_count" "$unrestorable_count"
  else
    printf 'restore: acted on %s window(s); %s unrestorable\n' "$restored_count" "$unrestorable_count"
  fi
  jq -r '.restored[] | "  + [\(.action)] \(.class) \(.workspace): \(.detail)"' <<<"$report"
  jq -r '.unrestorable[] | "  ! \(.class) (\(.address)) on \(.workspace): \(.reason)"' <<<"$report"
fi
