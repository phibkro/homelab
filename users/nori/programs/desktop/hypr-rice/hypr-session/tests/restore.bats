#!/usr/bin/env bats
# Red-green tests for restore.sh — the restore engine + adapter table.
# Requires: bats, jq (nix shell nixpkgs#bats nixpkgs#jq -c bats tests/restore.bats)
#
# hyprctl is PATH-shimmed by tests/fixtures/restore-bin/hyprctl, which
# records every `dispatch` call verbatim (one lua expression per line) to
# $dispatch_log and serves a canned post-restore `clients -j` list from
# tests/fixtures/<scenario>/clients-after.json. Assertions on dispatch
# syntax read $dispatch_log directly — this is what keeps the tests
# honest against the lua-builder-form gotcha (see
# Mnemopi recall: gotcha-hyprland-lua-migration).

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  restore=$script_dir/../restore.sh
  fixtures_root=$script_dir/fixtures
  PATH="$script_dir/fixtures/restore-bin:$PATH"
  export PATH

  export HYPRLAND_INSTANCE_SIGNATURE=bats-isolated-instance

  state_dir=$(mktemp -d)
  export HYPR_SESSION_STATE_DIR=$state_dir

  dispatch_log=$(mktemp)
  export HYPR_SESSION_TEST_DISPATCH_LOG=$dispatch_log

  # Fast timeouts by default so the "no match ever appears" path doesn't
  # actually wait — tests that exercise a slow-poll scenario override
  # these explicitly.
  export HYPR_SESSION_RESTORE_MAX_POLLS=2
  export HYPR_SESSION_RESTORE_POLL_INTERVAL=0.01
}

teardown() {
  rm -rf "$state_dir" "$dispatch_log"
  [[ -n ${extra_dirs+set} ]] && rm -rf "${extra_dirs[@]}"
  if [[ -n ${bg_pid-} ]]; then
    pkill -P "$bg_pid" 2>/dev/null || true
    kill "$bg_pid" 2>/dev/null || true
  fi
}

use_current() {
  # Installs a scenario's current.json as the resolved "current" snapshot.
  cp "$fixtures_root/$1/current.json" "$state_dir/current.json"
  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixtures_root/$1
}

@test "refuses an unknown schema version loudly" {
  use_current restore-unknown-version
  run bash "$restore"
  [ "$status" -ne 0 ]
  [[ $output == *version* ]]
  [ ! -s "$dispatch_log" ]
}

@test "errors when no snapshot is found at all" {
  run bash "$restore"
  [ "$status" -ne 0 ]
  [[ $output == *snapshot* ]]
}

@test "resolves a named session from named/<name>.json" {
  mkdir -p "$state_dir/named"
  cp "$fixtures_root/restore-default/current.json" "$state_dir/named/work.json"
  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixtures_root/restore-default
  run bash "$restore" work
  [ "$status" -eq 0 ]
  grep -q 'hl.dsp.exec_cmd' "$dispatch_log"
}

@test "--diff prints intended actions and dispatches nothing" {
  use_current restore-default
  run bash "$restore" --diff --json
  [ "$status" -eq 0 ]
  [ ! -s "$dispatch_log" ]
  diff_flag=$(jq '.diff' <<<"$output")
  [ "$diff_flag" = "true" ]
  restored_count=$(jq '.restored | length' <<<"$output")
  [ "$restored_count" = "1" ]
}

@test "default adapter respawns recorded cmdline into recorded workspace" {
  use_current restore-default
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -qF 'hl.dsp.exec_cmd("exec '"'"'zotero'"'"'", { workspace = "3" })' "$dispatch_log"
}

@test "spawn targeting a captured special workspace carries the silent suffix" {
  use_current restore-special
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -qF 'hl.dsp.exec_cmd("exec '"'"'zotero'"'"'", { workspace = "special:files silent" })' "$dispatch_log"
}

@test "ghostty adapter respawns with a cd into the captured cwd" {
  use_current restore-ghostty
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -qF "cd '/home/x/proj' && exec 'ghostty'" "$dispatch_log"
}

@test "dead-pid window is reported unrestorable and never dispatched" {
  use_current restore-dead-pid
  run bash "$restore" --json
  [ "$status" -eq 0 ]
  [ ! -s "$dispatch_log" ]
  reason=$(jq -r '.unrestorable[0].reason' <<<"$output")
  [[ $reason == *process* || $reason == *pid* ]]
  unrestorable_count=$(jq '.unrestorable | length' <<<"$output")
  [ "$unrestorable_count" = "1" ]
}

@test "restore never kills or closes existing windows" {
  use_current restore-default
  run bash "$restore"
  [ "$status" -eq 0 ]
  ! grep -q 'killactive\|window.close\|window.kill' "$dispatch_log"
}

@test "toggle_special uses the positional-string form, never the broken table form" {
  use_current restore-focus-special
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -qF 'hl.dsp.workspace.toggle_special("special:browser")' "$dispatch_log"
  ! grep -q 'toggle_special({' "$dispatch_log"
}

@test "focuses the captured focused window by its post-respawn address" {
  use_current restore-focus-special
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -qF 'hl.dsp.focus({ window = "address:0xfocusLIVE" })' "$dispatch_log"
}

@test "zen-beta windows are launched once and moved to captured layers in order, matched positionally (no identity available)" {
  use_current restore-zenbeta-order
  run bash "$restore" --json
  [ "$status" -eq 0 ]
  # exactly one bare launch for the whole class, not one per captured window
  launch_count=$(grep -c 'hl.dsp.exec_cmd("exec '"'"'zen-beta'"'"'")' "$dispatch_log")
  [ "$launch_count" = "1" ]
  grep -qF 'hl.dsp.window.move({ workspace = "special:web1", silent = true, window = "address:0xzenLIVEa" })' "$dispatch_log"
  grep -qF 'hl.dsp.window.move({ workspace = "special:web2", silent = true, window = "address:0xzenLIVEb" })' "$dispatch_log"
  restored_count=$(jq '.restored | length' <<<"$output")
  [ "$restored_count" -ge 3 ] # 1 launch + 2 moves
}

@test "code adapter that never sees a matching window times out and reports unrestorable, without crashing" {
  use_current restore-code-timeout
  run bash "$restore" --json
  [ "$status" -eq 0 ]
  grep -qF 'hl.dsp.exec_cmd("exec '"'"'code'"'"'")' "$dispatch_log"
  ! grep -q 'window.move' "$dispatch_log"
  unrestorable_count=$(jq '.unrestorable | length' <<<"$output")
  [ "$unrestorable_count" = "1" ]
  reason=$(jq -r '.unrestorable[0].reason' <<<"$output")
  [[ $reason == *timeout* || $reason == *"did not appear"* ]]
}

@test "code adapter launches once and moves the matched window to its captured layer by identity, not title" {
  # Real spawned process so /proc/<pid>/cmdline genuinely contains an
  # existing directory — mirrors capture.bats' live-process technique;
  # a fake pid can't be read back through /proc.
  extra_tmp=$(mktemp -d)
  project_dir=$extra_tmp/my-project
  mkdir -p "$project_dir"
  fifo=$(mktemp -u)
  mkfifo "$fifo"
  cat "$project_dir" "$fifo" </dev/null >/dev/null 2>&1 &
  bg_pid=$!
  for _ in $(seq 1 50); do
    [[ -e /proc/$bg_pid/cmdline ]] && break
    sleep 0.1
  done

  fixture_dir=$(mktemp -d)
  extra_dirs=("$extra_tmp" "$fixture_dir" "$fifo")
  jq -n --arg pd "$project_dir" '{
    version: 1,
    captured_at: "2026-07-20T10:00:00Z",
    monitors: [{ id: 0, name: "DP-3", width: 3440, height: 1440 }],
    focus: { focused_window: null, monitors: [{ monitor: "DP-3", active_workspace: "1", special_workspace: null }] },
    windows: [{
      address: "0xcode0002",
      class: "code",
      title: "my-project - Visual Studio Code",
      workspace: "special:code",
      floating: false,
      geometry: null,
      process: { cwd: "/home/x", cmdline: ["code", $pd] },
      identity: { kind: "editor", value: $pd }
    }]
  }' >"$state_dir/current.json"

  jq -n --argjson pid "$bg_pid" '[{
    address: "0xcodeLIVE",
    class: "code",
    title: "my-project - Visual Studio Code",
    workspace: { id: 1, name: "1" },
    floating: false,
    at: [0, 0], size: [1, 1],
    pid: $pid
  }]' >"$fixture_dir/clients-after.json"

  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixture_dir
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -qF 'hl.dsp.exec_cmd("exec '"'"'code'"'"'")' "$dispatch_log"
  grep -qF 'hl.dsp.window.move({ workspace = "special:code", silent = true, window = "address:0xcodeLIVE" })' "$dispatch_log"
}

@test "floating geometry is reapplied after respawn (best-effort, see restore.sh header)" {
  use_current restore-floating-geometry
  run bash "$restore"
  [ "$status" -eq 0 ]
  grep -q '0xfloatLIVE' "$dispatch_log"
}

@test "--json emits the full report shape: diff, restored, skipped_already_present, unrestorable" {
  use_current restore-default
  run bash "$restore" --json
  [ "$status" -eq 0 ]
  jq -e 'has("diff") and has("restored") and has("skipped_already_present") and has("unrestorable")' <<<"$output" >/dev/null
}

@test "skipped_already_present is always empty in v1 and says so" {
  use_current restore-default
  run bash "$restore" --json
  [ "$status" -eq 0 ]
  windows=$(jq '.skipped_already_present.windows | length' <<<"$output")
  [ "$windows" = "0" ]
  note=$(jq -r '.skipped_already_present.note' <<<"$output")
  [[ $note == *"v1"* || $note == *"not"* ]]
}

@test "rejects a missing hyprctl on PATH loudly when it actually needs to dispatch" {
  use_current restore-default
  real_bash=$(command -v bash)
  run env PATH=/nonexistent HYPR_SESSION_STATE_DIR="$state_dir" HYPRLAND_INSTANCE_SIGNATURE=bats-isolated-instance "$real_bash" "$restore"
  [ "$status" -ne 0 ]
  [[ $output == *hyprctl* ]]
}

# ---- schema seam: the earlier "resolves a named session" test above
# hand-copies a RAW snapshot straight into named/, which never exercises
# cli.sh's actual write contract (cmd_save in cli.sh) and let a real
# save/restore mismatch through the unit suite once (cli.sh briefly
# wrapped as {label, created_at, snapshot} instead of embedding the
# label/created_at fields into the snapshot itself). Driving the REAL
# cli.sh producer — not a hand-rolled guess at its shape — is what keeps
# this test honest against cli.sh's contract as the single source of
# truth for the named-file format.
@test "resolves a session saved by the real cli.sh save subcommand" {
  cp "$fixtures_root/restore-default/current.json" "$state_dir/current.json"
  run bash "$script_dir/../cli.sh" save work
  [ "$status" -eq 0 ]
  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixtures_root/restore-default
  run bash "$restore" work
  [ "$status" -eq 0 ]
  grep -q 'hl.dsp.exec_cmd' "$dispatch_log"
}

# ---- --diff must never fabricate an unrestorable entry for a pending
# record (floating / launch-once / focused) it deliberately never tried
# to resolve — diff mode skips the reconciliation poll entirely, so
# falling through to the live-resolution "not found" branches lies about
# what was attempted.
@test "--diff never fabricates unrestorable entries for the captured focused window" {
  use_current restore-focus-special
  run bash "$restore" --diff --json
  [ "$status" -eq 0 ]
  [ ! -s "$dispatch_log" ]
  unrestorable_count=$(jq '.unrestorable | length' <<<"$output")
  [ "$unrestorable_count" = "0" ]
  action=$(jq -r '.restored[] | select(.action == "focus") | .action' <<<"$output")
  [ "$action" = "focus" ]
}

@test "--diff never fabricates unrestorable entries for floating geometry" {
  use_current restore-floating-geometry
  run bash "$restore" --diff --json
  [ "$status" -eq 0 ]
  [ ! -s "$dispatch_log" ]
  unrestorable_count=$(jq '.unrestorable | length' <<<"$output")
  [ "$unrestorable_count" = "0" ]
}

# The end-to-end VM verifies both position and size reapplication against a
# real Hyprland Lua-mode compositor.
@test "geometry report identifies verified position and size reapply" {
  use_current restore-floating-geometry
  run bash "$restore" --json
  [ "$status" -eq 0 ]
  pos_detail=$(jq -r '.restored[] | select(.action == "position") | .detail' <<<"$output")
  [[ $pos_detail == *verified* ]]
  size_detail=$(jq -r '.restored[] | select(.action == "size") | .detail' <<<"$output")
  [[ $size_detail == *verified* ]]
}
