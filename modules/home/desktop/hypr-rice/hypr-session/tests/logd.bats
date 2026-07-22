#!/usr/bin/env bats
# Red-green tests for hypr-session-logd — debounced event-log capture.
# Requires: bats, jq, socat
#   (nix shell nixpkgs#bats nixpkgs#jq nixpkgs#socat -c bats tests/logd.bats)
#
# No live compositor: a socat UNIX-LISTEN stands in for Hyprland's socket2,
# fed via a FIFO the test writes to; capture.sh is swapped for a stub via
# HYPR_SESSION_CAPTURE_CMD (tests/fixtures/logd-stub/capture-stub.sh).

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  logd=$script_dir/../logd.sh
  stub_capture=$script_dir/fixtures/logd-stub/capture-stub.sh

  runtime_dir=$(mktemp -d)
  state_dir=$(mktemp -d)
  calls_file=$(mktemp -u)
  fail_flag=$(mktemp -u)
  events_fifo=$(mktemp -u)
  mkfifo "$events_fifo"

  export XDG_RUNTIME_DIR=$runtime_dir
  export HYPRLAND_INSTANCE_SIGNATURE=bats-logd-instance
  export HYPR_SESSION_STATE_DIR=$state_dir
  export HYPR_SESSION_CAPTURE_CMD=$stub_capture
  export HYPR_SESSION_STUB_CALLS_FILE=$calls_file
  export HYPR_SESSION_STUB_FAIL_FLAG=$fail_flag
  # short enough for a fast test loop, long enough to observe coalescing
  export HYPR_SESSION_DEBOUNCE_SECONDS=0.3
  export HYPR_SESSION_LOG_MAX_ENTRIES=200

  socket_dir="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE"
  mkdir -p "$socket_dir"
  socket_path="$socket_dir/.socket2.sock"

  # fake compositor: relay whatever the test writes into $events_fifo to
  # any client connecting to the unix socket. -u = unidirectional
  # fifo -> socket, matching real socket2 (compositor writes, we read).
  socat -u OPEN:"$events_fifo,rdonly" UNIX-LISTEN:"$socket_path" &
  relay_pid=$!

  # hold a persistent writer open on the fifo so each individual `printf`
  # below doesn't re-trigger a fifo open/close (which would EOF the relay
  # between messages). Closed explicitly in teardown.
  exec {events_fd}>"$events_fifo"

  logd_pid=""
}

teardown() {
  [[ -n $logd_pid ]] && kill -TERM "$logd_pid" 2>/dev/null
  [[ -n $logd_pid ]] && wait "$logd_pid" 2>/dev/null
  eval "exec ${events_fd}>&-" 2>/dev/null || true
  kill "$relay_pid" 2>/dev/null || true
  rm -rf "$runtime_dir" "$state_dir"
  rm -f "$calls_file" "$fail_flag" "$events_fifo"
}

send_event() {
  printf '%s\n' "$1" >&"$events_fd"
}

start_logd() {
  bash "$logd" &
  logd_pid=$!
}

wait_for_socket() {
  for _ in $(seq 1 50); do
    [[ -S $socket_path ]] && return 0
    sleep 0.1
  done
  return 1
}

@test "writes current.json and appends log.jsonl after a debounced topology event" {
  start_logd
  send_event 'openwindow>>0xdead,1,ghostty,term'
  sleep 0.8

  [ -f "$state_dir/current.json" ]
  version=$(jq '.version' "$state_dir/current.json")
  [ "$version" = "1" ]

  [ -f "$state_dir/log.jsonl" ]
  lines=$(wc -l <"$state_dir/log.jsonl")
  [ "$lines" -eq 1 ]
}

@test "coalesces rapid successive events into a single capture" {
  start_logd
  send_event 'openwindow>>0xdead,1,ghostty,term'
  sleep 0.05
  send_event 'movewindow>>0xdead,2'
  sleep 0.05
  send_event 'workspace>>2'
  sleep 0.8

  calls=$(<"$calls_file")
  [ "$calls" -eq 1 ]
}

@test "ignores non-topology events, no capture fires" {
  start_logd
  send_event 'mouse>>irrelevant'
  sleep 0.8

  [ ! -f "$calls_file" ]
  [ ! -f "$state_dir/current.json" ]
}

@test "prunes log.jsonl to the configured ring bound" {
  export HYPR_SESSION_LOG_MAX_ENTRIES=3
  start_logd

  for i in 1 2 3 4 5; do
    send_event "openwindow>>0xdead$i,1,ghostty,term"
    sleep 0.8
  done

  lines=$(wc -l <"$state_dir/log.jsonl")
  [ "$lines" -eq 3 ]
  # ring keeps the MOST RECENT entries, not the oldest
  last_call=$(jq '.call' "$state_dir/current.json")
  [ "$last_call" -eq 5 ]
  oldest_kept_call=$(head -n1 "$state_dir/log.jsonl" | jq '.call')
  [ "$oldest_kept_call" -eq 3 ]
}

@test "survives a transient capture failure and keeps running for the next event" {
  touch "$fail_flag"
  start_logd
  send_event 'openwindow>>0xdead,1,ghostty,term'
  sleep 0.8

  # failed capture: no snapshot written, but the daemon is still alive
  [ ! -f "$state_dir/current.json" ]
  kill -0 "$logd_pid"

  rm -f "$fail_flag"
  send_event 'workspace>>2'
  sleep 0.8

  [ -f "$state_dir/current.json" ]
}

@test "shuts down cleanly on SIGTERM" {
  start_logd
  wait_for_socket
  # watchdog so a stuck daemon fails the test loudly instead of hanging
  # the suite — `wait` can't target a non-child pid, so we can't wrap it
  # in `timeout` directly.
  ( sleep 5; kill -9 "$logd_pid" 2>/dev/null ) &
  watchdog_pid=$!
  kill -TERM "$logd_pid"
  wait "$logd_pid"
  status=$?
  kill "$watchdog_pid" 2>/dev/null
  logd_pid=""
  [ "$status" -eq 0 ]
}
