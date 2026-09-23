#!/usr/bin/env bats
# Red-green tests for capture.sh — snapshot schema v1.
# Requires: bats, jq (nix shell nixpkgs#bats nixpkgs#jq -c bats tests/capture.bats)

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  capture=$script_dir/../capture.sh
  fixtures_root=$script_dir/fixtures
  PATH="$script_dir/bin:$PATH"
  export PATH

  # Point at an isolated instance signature — capture.sh must never touch
  # the real Hyprland socket. The PATH-shim hyprctl ignores this value
  # (it replays fixtures), but capture.sh must not clobber it either.
  export HYPRLAND_INSTANCE_SIGNATURE=bats-isolated-instance

  state_dir=$(mktemp -d)
  export HYPR_SESSION_STATE_DIR=$state_dir
}

teardown() {
  rm -rf "$state_dir"
  [[ -n ${extra_dirs+set} ]] && rm -rf "${extra_dirs[@]}"
  if [[ -n ${sleep_pid-} ]]; then
    # some fixtures spawn a blocking wrapper whose own `sleep` runs as a
    # child, not an exec-replace — reap that child too, not just the pid
    # bash handed back.
    pkill -P "$sleep_pid" 2>/dev/null || true
    kill "$sleep_pid" 2>/dev/null || true
  fi
}

use_fixture() {
  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixtures_root/$1
}

@test "emits version 1 and an ISO8601 captured_at" {
  use_fixture basic
  run bash "$capture"
  [ "$status" -eq 0 ]
  version=$(jq '.version' <<<"$output")
  [ "$version" = "1" ]
  captured_at=$(jq -r '.captured_at' <<<"$output")
  [[ $captured_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "captures monitor identity fields" {
  use_fixture basic
  run bash "$capture"
  [ "$status" -eq 0 ]
  name=$(jq -r '.monitors[0].name' <<<"$output")
  [ "$name" = "DP-3" ]
  width=$(jq '.monitors[0].width' <<<"$output")
  [ "$width" = "3440" ]
  height=$(jq '.monitors[0].height' <<<"$output")
  [ "$height" = "1440" ]
}

@test "captures focused window address and per-monitor workspace state" {
  use_fixture basic
  run bash "$capture"
  [ "$status" -eq 0 ]
  focused=$(jq -r '.focus.focused_window' <<<"$output")
  [ "$focused" = "0x60cdafc982a0" ]
  active=$(jq -r '.focus.monitors[0].active_workspace' <<<"$output")
  [ "$active" = "1" ]
  special=$(jq -r '.focus.monitors[0].special_workspace' <<<"$output")
  [ "$special" = "special:browser" ]
}

@test "no focused window and no special workspace surface as null" {
  use_fixture no-focus
  run bash "$capture"
  [ "$status" -eq 0 ]
  focused=$(jq '.focus.focused_window' <<<"$output")
  [ "$focused" = "null" ]
  special=$(jq '.focus.monitors[0].special_workspace' <<<"$output")
  [ "$special" = "null" ]
  windows_count=$(jq '.windows | length' <<<"$output")
  [ "$windows_count" = "0" ]
}

@test "each window carries class, title and workspace name" {
  use_fixture basic
  run bash "$capture"
  [ "$status" -eq 0 ]
  zotero_workspace=$(jq -r '.windows[] | select(.class == "Zotero") | .workspace' <<<"$output")
  [ "$zotero_workspace" = "special:files" ]
  zotero_title=$(jq -r '.windows[] | select(.class == "Zotero") | .title' <<<"$output")
  [ "$zotero_title" = "My Library - Zotero" ]
}

@test "non-floating windows carry null geometry" {
  use_fixture basic
  run bash "$capture"
  [ "$status" -eq 0 ]
  geometry=$(jq '.windows[] | select(.class == "Zotero") | .geometry' <<<"$output")
  [ "$geometry" = "null" ]
}

@test "floating windows carry geometry from at/size" {
  use_fixture floating
  run bash "$capture"
  [ "$status" -eq 0 ]
  floating=$(jq '.windows[0].floating' <<<"$output")
  [ "$floating" = "true" ]
  x=$(jq '.windows[0].geometry.x' <<<"$output")
  [ "$x" = "700" ]
  y=$(jq '.windows[0].geometry.y' <<<"$output")
  [ "$y" = "500" ]
  width=$(jq '.windows[0].geometry.width' <<<"$output")
  [ "$width" = "700" ]
  height=$(jq '.windows[0].geometry.height' <<<"$output")
  [ "$height" = "500" ]
}

@test "dead pid yields null process and null identity, not a crash" {
  use_fixture dead-pid
  run bash "$capture"
  [ "$status" -eq 0 ]
  process=$(jq '.windows[0].process' <<<"$output")
  [ "$process" = "null" ]
  identity=$(jq '.windows[0].identity' <<<"$output")
  [ "$identity" = "null" ]
}

@test "multi-window single-pid app shares process info across windows, read once per pid" {
  use_fixture basic
  run bash "$capture"
  [ "$status" -eq 0 ]
  ghostty_processes=$(jq -c '[.windows[] | select(.class == "com.mitchellh.ghostty") | .process] | unique' <<<"$output")
  count=$(jq 'length' <<<"$ghostty_processes")
  # both ghostty windows share the same (nonexistent, dead) pid -> one
  # shared null value, not divergent per-window artifacts.
  [ "$count" = "1" ]
}

@test "enrichment reads real /proc data for a live spawned process (cwd + cmdline)" {
  extra_tmp=$(mktemp -d)
  (cd "$extra_tmp" && exec sleep 600) </dev/null >/dev/null 2>&1 &
  sleep_pid=$!
  # wait for the kernel to actually populate /proc/<pid>/cwd
  for _ in $(seq 1 50); do
    [[ -e /proc/$sleep_pid/cwd ]] && break
    sleep 0.1
  done

  fixture_dir=$(mktemp -d)
  extra_dirs=("$extra_tmp" "$fixture_dir")
  cp "$fixtures_root/basic/monitors.json" "$fixture_dir/monitors.json"
  cp "$fixtures_root/basic/activewindow.json" "$fixture_dir/activewindow.json"
  jq -n --argjson pid "$sleep_pid" '[{
    address: "0xliveproc0001",
    at: [0,0], size: [1,1],
    workspace: {id: 1, name: "1"},
    floating: false, monitor: 0,
    class: "com.mitchellh.ghostty",
    title: "live", pid: $pid
  }]' > "$fixture_dir/clients.json"

  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixture_dir
  run bash "$capture"
  [ "$status" -eq 0 ]

  cwd=$(jq -r '.windows[0].process.cwd' <<<"$output")
  [ "$cwd" = "$extra_tmp" ]
  cmdline=$(jq -c '.windows[0].process.cmdline' <<<"$output")
  [ "$cmdline" = '["sleep","600"]' ]
  identity_kind=$(jq -r '.windows[0].identity.kind' <<<"$output")
  [ "$identity_kind" = "terminal" ]
  identity_value=$(jq -r '.windows[0].identity.value' <<<"$output")
  [ "$identity_value" = "$extra_tmp" ]
}

@test "editor identity derives project folder from cmdline path argument" {
  extra_tmp=$(mktemp -d)
  project_dir=$extra_tmp/my-project
  mkdir -p "$project_dir"
  # real GNU `sleep` rejects a non-numeric extra arg outright ("invalid
  # time interval"), so a literal `sleep 600 "$project_dir" &` dies before
  # /proc ever sees it, and `bash -c '<cmd>' _ args...` doesn't work either
  # — bash exec-optimizes an unreferenced-args single command, discarding
  # them before they ever reach argv. Use `cat <path> <fifo>` instead: cat
  # touches (and, for a plain file, immediately exhausts) the path arg,
  # then blocks reading the empty FIFO — no interpreter indirection, so
  # /proc/<pid>/cmdline is exactly ["cat","$project_dir","$fifo"].
  fifo=$(mktemp -u)
  mkfifo "$fifo"
  cat "$project_dir" "$fifo" </dev/null >/dev/null 2>&1 &
  sleep_pid=$!
  for _ in $(seq 1 50); do
    [[ -e /proc/$sleep_pid/cmdline ]] && break
    sleep 0.1
  done

  fixture_dir=$(mktemp -d)
  extra_dirs=("$extra_tmp" "$fixture_dir" "$fifo")
  cp "$fixtures_root/basic/monitors.json" "$fixture_dir/monitors.json"
  cp "$fixtures_root/basic/activewindow.json" "$fixture_dir/activewindow.json"
  jq -n --argjson pid "$sleep_pid" '[{
    address: "0xliveproc0002",
    at: [0,0], size: [1,1],
    workspace: {id: 1, name: "1"},
    floating: false, monitor: 0,
    class: "code",
    title: "my-project - Visual Studio Code", pid: $pid
  }]' > "$fixture_dir/clients.json"

  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixture_dir
  run bash "$capture"
  [ "$status" -eq 0 ]

  identity_kind=$(jq -r '.windows[0].identity.kind' <<<"$output")
  [ "$identity_kind" = "editor" ]
  identity_value=$(jq -r '.windows[0].identity.value' <<<"$output")
  [ "$identity_value" = "$project_dir" ]
}

@test "media identity derives file path from cmdline" {
  extra_tmp=$(mktemp -d)
  media_file=$extra_tmp/movie.mp4
  : >"$media_file"
  # see the editor test above for why: `cat <path> <fifo>` reads (and
  # exhausts) the path arg then blocks on the empty FIFO.
  fifo=$(mktemp -u)
  mkfifo "$fifo"
  cat "$media_file" "$fifo" </dev/null >/dev/null 2>&1 &
  sleep_pid=$!
  for _ in $(seq 1 50); do
    [[ -e /proc/$sleep_pid/cmdline ]] && break
    sleep 0.1
  done

  fixture_dir=$(mktemp -d)
  extra_dirs=("$extra_tmp" "$fixture_dir" "$fifo")
  cp "$fixtures_root/basic/monitors.json" "$fixture_dir/monitors.json"
  cp "$fixtures_root/basic/activewindow.json" "$fixture_dir/activewindow.json"
  jq -n --argjson pid "$sleep_pid" '[{
    address: "0xliveproc0003",
    at: [0,0], size: [1,1],
    workspace: {id: 1, name: "1"},
    floating: false, monitor: 0,
    class: "vlc",
    title: "movie.mp4 - VLC", pid: $pid
  }]' > "$fixture_dir/clients.json"

  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixture_dir
  run bash "$capture"
  [ "$status" -eq 0 ]

  identity_kind=$(jq -r '.windows[0].identity.kind' <<<"$output")
  [ "$identity_kind" = "media" ]
  identity_value=$(jq -r '.windows[0].identity.value' <<<"$output")
  [ "$identity_value" = "$media_file" ]
}

@test "fallback class with no matching adapter yields null identity even with live process data" {
  extra_tmp=$(mktemp -d)
  (cd "$extra_tmp" && exec sleep 600) </dev/null >/dev/null 2>&1 &
  sleep_pid=$!
  for _ in $(seq 1 50); do
    [[ -e /proc/$sleep_pid/cwd ]] && break
    sleep 0.1
  done

  fixture_dir=$(mktemp -d)
  extra_dirs=("$extra_tmp" "$fixture_dir")
  cp "$fixtures_root/basic/monitors.json" "$fixture_dir/monitors.json"
  cp "$fixtures_root/basic/activewindow.json" "$fixture_dir/activewindow.json"
  jq -n --argjson pid "$sleep_pid" '[{
    address: "0xliveproc0004",
    at: [0,0], size: [1,1],
    workspace: {id: 1, name: "1"},
    floating: false, monitor: 0,
    class: "Unknown.RandomApp",
    title: "Random", pid: $pid
  }]' > "$fixture_dir/clients.json"

  export HYPR_SESSION_TEST_FIXTURES_DIR=$fixture_dir
  run bash "$capture"
  [ "$status" -eq 0 ]

  identity=$(jq '.windows[0].identity' <<<"$output")
  [ "$identity" = "null" ]
  # process data is still captured even though no identity adapter matched
  cwd=$(jq -r '.windows[0].process.cwd' <<<"$output")
  [ "$cwd" = "$extra_tmp" ]
}

@test "rejects a missing hyprctl on PATH loudly" {
  use_fixture basic
  # NixOS has no /usr/bin/bash or /bin/bash — resolve the real bash by
  # absolute path first so only the SCRIPT's internal PATH (used to find
  # hyprctl) is starved, not the invocation of bash itself.
  real_bash=$(command -v bash)
  run env PATH=/nonexistent "$real_bash" "$capture"
  [ "$status" -ne 0 ]
  [[ $output == *hyprctl* ]]
}
