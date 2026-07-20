#!/usr/bin/env bash
# hypr-session-logd — subscribes to Hyprland's socket2 event stream and,
# on window-topology churn (debounced), appends a full snapshot to a
# bounded ring log. See
# docs/specs/2026-07-20-hypr-session-persistence-design.md § Capture:
# "the last log entry is always the pre-shutdown state by construction —
# no shutdown hook exists to race." This is what makes that true: there is
# no exit-time capture anywhere in this script.
#
# Requires on PATH: socat, jq, bash, coreutils (mktemp, mv, tail, wc),
# and capture.sh (same directory, or override via
# HYPR_SESSION_CAPTURE_CMD). Nix wrapping closes over these; login PATH
# is thin.
#
# Env:
#   HYPRLAND_INSTANCE_SIGNATURE + XDG_RUNTIME_DIR
#                                 derive the socket2 path
#                                 ($XDG_RUNTIME_DIR/hypr/$SIG/.socket2.sock).
#                                 Passed through untouched, same contract
#                                 as capture.sh, so tests can point both at
#                                 an isolated fixture tree (a socat
#                                 UNIX-LISTEN standing in for Hyprland).
#   HYPR_SESSION_STATE_DIR       where current.json / log.jsonl live.
#                                 Default: ~/.local/state/hypr-session
#   HYPR_SESSION_DEBOUNCE_SECONDS  quiet period after the last topology
#                                 event before capturing. Default: 2
#   HYPR_SESSION_LOG_MAX_ENTRIES  ring bound on log.jsonl entry count.
#                                 Default: 500
#   HYPR_SESSION_CAPTURE_CMD     capture command to run. Default:
#                                 capture.sh next to this script; tests
#                                 point this at a stub instead.
set -uo pipefail
# NOT -e: a transient capture failure (do_capture) must not kill the
# daemon's event loop — it's caught and logged instead (see do_capture).

# Trap installed FIRST, before any setup work (mkdir, socket wait, etc.) —
# a SIGTERM arriving in that window would otherwise hit bash's default
# (uncaught) disposition and skip cleanup entirely.
client_pid=""
cleanup() {
  [[ -n $client_pid ]] && kill "$client_pid" 2>/dev/null
  exit 0
}
trap cleanup SIGTERM SIGINT

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

state_dir="$(hypr_session_state_dir)"
debounce_seconds="${HYPR_SESSION_DEBOUNCE_SECONDS:-2}"
log_max_entries="${HYPR_SESSION_LOG_MAX_ENTRIES:-500}"
capture_cmd="${HYPR_SESSION_CAPTURE_CMD:-$script_dir/capture.sh}"
socket_path="${XDG_RUNTIME_DIR:-}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"

if ! command -v socat >/dev/null 2>&1; then
  echo "hypr-session-logd: socat not found on PATH" >&2
  exit 1
fi

mkdir -p "$state_dir"
current_file="$state_dir/current.json"
log_file="$state_dir/log.jsonl"

# window-topology events worth recapturing on (spec § Capture: "openwindow
# / closewindow / movewindow / workspace / activespecial ..."). Extend
# this case as new topology-affecting events turn up; unmatched lines
# (mouse moves, urgent, etc.) are noise for session-snapshot purposes.
is_topology_event() {
  case "$1" in
  openwindow'>>'* | closewindow'>>'* | movewindow'>>'* | movewindowv2'>>'* | \
    workspace'>>'* | workspacev2'>>'* | moveworkspace'>>'* | moveworkspacev2'>>'* | \
    activespecial'>>'* | fullscreen'>>'* | changefloatingmode'>>'*) return 0 ;;
  *) return 1 ;;
  esac
}

do_capture() {
  local snapshot
  if ! snapshot=$(bash "$capture_cmd" 2>&1); then
    echo "hypr-session-logd: capture failed, keeping previous state: $snapshot" >&2
    return
  fi

  local tmp
  tmp=$(mktemp "$state_dir/.current.XXXXXX.json")
  printf '%s\n' "$snapshot" >"$tmp"
  mv -f "$tmp" "$current_file"

  printf '%s\n' "$snapshot" >>"$log_file"
  prune_log
}

prune_log() {
  prune_ring "$log_file" "$log_max_entries" >/dev/null
}

# Hyprland (or, in tests, the fixture's socat listener) may not have the
# socket up yet at service start — poll rather than fail immediately.
for _ in $(seq 1 50); do
  [[ -S $socket_path ]] && break
  sleep 0.1
done
if [[ ! -S $socket_path ]]; then
  echo "hypr-session-logd: socket2 never appeared at $socket_path" >&2
  exit 1
fi

# Process substitution on a simple command sets $! to the substituted
# process's pid (bash ≥4.4) — no coproc bookkeeping needed.
exec 3< <(socat -u UNIX-CONNECT:"$socket_path" STDIO)
client_pid=$!

pending=0
while true; do
  if IFS= read -r -t "$debounce_seconds" line <&3; then
    is_topology_event "$line" && pending=1
  else
    status=$?
    if ((status > 128)); then
      # debounce timeout, no line arrived within the quiet window
      if ((pending)); then
        do_capture
        pending=0
      fi
    else
      echo "hypr-session-logd: socket2 stream closed" >&2
      break
    fi
  fi
done

cleanup
