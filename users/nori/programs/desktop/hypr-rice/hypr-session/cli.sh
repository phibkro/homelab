#!/usr/bin/env bash
# hypr-session CLI — tmux-style session management over the snapshots
# hypr-session-logd writes. This script only reads/writes
# $HYPR_SESSION_STATE_DIR; it never touches Hyprland directly. `restore`
# is a separate concern (docs/specs/2026-07-20-hypr-session-persistence-design.md
# § Restore engine) owned by the sibling restore.sh — delegated whole-cloth
# so this script stays free of dispatch/lua-builder concerns.
#
# Requires on PATH: jq, coreutils (basename, date, mv, mktemp, wc, tail).
# Nix wrapping closes over these; login PATH is thin.
#
# State layout ($HYPR_SESSION_STATE_DIR, default ~/.local/state/hypr-session):
#   current.json       always-valid head snapshot (written by hypr-session-logd)
#   log.jsonl           bounded ring of historical snapshots (written by logd)
#   named/<name>.json   raw v1 snapshot (same shape as current.json) with
#                        label/created_at embedded as extra top-level
#                        fields ("a label in snapshot metadata" — design
#                        doc § Adopted) — restore.sh reads this path
#                        directly as a snapshot, so it must never be
#                        wrapped. This script's write surface.
#
# Env:
#   HYPR_SESSION_STATE_DIR        state root; default ~/.local/state/hypr-session
#   HYPR_SESSION_LOG_MAX_ENTRIES  ring bound `prune` trims log.jsonl to; default
#                                  500 — same knob logd.sh's own auto-prune reads
#                                  (see lib.sh's prune_ring), so a manual `prune`
#                                  and the daemon's post-capture prune can never
#                                  disagree on the bound.
#   HYPRLAND_INSTANCE_SIGNATURE  never read here — inherited untouched into the
#                                 environment `restore` execs into, so tests can
#                                 point it at an isolated instance.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
restore_bin="$script_dir/restore.sh"

state_dir="$(hypr_session_state_dir)"
named_dir="$state_dir/named"
current_file="$state_dir/current.json"
log_file="$state_dir/log.jsonl"

usage() {
  cat <<'EOF'
Usage: hypr-session <subcommand> [args] [--json]

  list                    named sessions + the auto "last" head
  save <name>             freeze current.json into named/<name>.json
  rename <old> <new>      rename a named session
  delete <name>           delete a named session
  prune                   trim log.jsonl to HYPR_SESSION_LOG_MAX_ENTRIES
  restore [name] [--diff] delegated to restore.sh

Every subcommand accepts --json for machine-readable output.
EOF
}

die() {
  echo "hypr-session: $*" >&2
  exit 1
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Splits "$@" into the global JSON flag (0/1) and POSITIONAL (everything
# else) so each subcommand stays agnostic about where --json lands.
parse_flags() {
  JSON=0
  POSITIONAL=()
  local arg
  for arg in "$@"; do
    if [[ $arg == "--json" ]]; then
      JSON=1
    else
      POSITIONAL+=("$arg")
    fi
  done
}

# Auto-label for the unnamed "last" head: the basename of the identity
# value shared by the most windows (dominant project/cwd), falling back to
# a generic label when no window carries an identity — mirrors Herdr's
# "labels derive from identity when unset" (see design doc § Adopted).
auto_label() {
  local snapshot_file="$1" val
  val=$(jq -r '
    [.windows[].identity.value // empty]
    | group_by(.)
    | sort_by(-length)
    | (.[0][0] // "null")
  ' "$snapshot_file")
  if [[ $val == "null" ]]; then
    echo "session"
  else
    basename "$val"
  fi
}

cmd_list() {
  mkdir -p "$named_dir"
  local entries=() f name label created_at
  for f in "$named_dir"/*.json; do
    [[ -e $f ]] || continue
    name=$(basename "$f" .json)
    label=$(jq -r '.label' "$f")
    created_at=$(jq -r '.created_at' "$f")
    entries+=("$(jq -nc --arg name "$name" --arg label "$label" --arg created_at "$created_at" \
      '{name: $name, label: $label, created_at: $created_at}')")
  done
  local named_json
  if [[ ${#entries[@]} -eq 0 ]]; then
    named_json="[]"
  else
    named_json=$(printf '%s\n' "${entries[@]}" | jq -s '.')
  fi

  local last_json=null
  if [[ -f $current_file ]]; then
    local captured_at head_label
    captured_at=$(jq -r '.captured_at' "$current_file")
    head_label=$(auto_label "$current_file")
    last_json=$(jq -nc --arg captured_at "$captured_at" --arg label "$head_label" \
      '{captured_at: $captured_at, label: $label}')
  fi

  if [[ $JSON -eq 1 ]]; then
    jq -nc --argjson named "$named_json" --argjson last "$last_json" \
      '{named: $named, last: $last}'
  else
    print_list_human "$named_json" "$last_json"
  fi
}

print_list_human() {
  local named_json="$1" last_json="$2"
  local named_count
  named_count=$(jq 'length' <<<"$named_json")
  if [[ $last_json == "null" && $named_count -eq 0 ]]; then
    echo "No sessions."
    return 0
  fi
  if [[ $last_json != "null" ]]; then
    jq -r '"last\t" + .captured_at + "\t" + .label' <<<"$last_json"
  fi
  jq -r '.[] | .name + "\t" + .created_at + "\t" + .label' <<<"$named_json"
}

cmd_save() {
  local name="${1-}"
  [[ -n $name ]] || die "save: missing session name (usage: save <name>)"
  [[ -f $current_file ]] || die "save: no current session to freeze (missing $current_file)"
  mkdir -p "$named_dir"
  local dest="$named_dir/$name.json"
  [[ -e $dest ]] && die "save: session '$name' already exists — delete or rename it first"
  local created_at named_snapshot
  created_at=$(now_iso)
  # Embed label/created_at INTO the snapshot rather than wrapping it —
  # named/<name>.json must stay a raw v1 snapshot so restore.sh (which
  # reads .version/.windows/.focus at the top level) can consume it
  # unmodified, same as current.json.
  named_snapshot=$(jq --arg label "$name" --arg created_at "$created_at" \
    '. + {label: $label, created_at: $created_at}' "$current_file")
  printf '%s\n' "$named_snapshot" >"$dest"
  if [[ $JSON -eq 1 ]]; then
    printf '%s\n' "$named_snapshot"
  else
    echo "Saved session '$name' ($created_at)"
  fi
}

cmd_rename() {
  local old="${1-}" new="${2-}"
  [[ -n $old && -n $new ]] || die "rename: usage: rename <old> <new>"
  local old_file="$named_dir/$old.json" new_file="$named_dir/$new.json"
  [[ -f $old_file ]] || die "rename: no such session '$old'"
  [[ -e $new_file ]] && die "rename: session '$new' already exists — delete it first"
  local renamed_snapshot
  renamed_snapshot=$(jq --arg label "$new" '.label = $label' "$old_file")
  printf '%s\n' "$renamed_snapshot" >"$new_file"
  rm -f "$old_file"
  if [[ $JSON -eq 1 ]]; then
    printf '%s\n' "$renamed_snapshot"
  else
    echo "Renamed session '$old' -> '$new'"
  fi
}

cmd_delete() {
  local name="${1-}"
  [[ -n $name ]] || die "delete: missing session name"
  local f="$named_dir/$name.json"
  [[ -f $f ]] || die "delete: no such session '$name'"
  rm -f "$f"
  if [[ $JSON -eq 1 ]]; then
    jq -nc --arg name "$name" '{deleted: $name}'
  else
    echo "Deleted session '$name'"
  fi
}

# Manual/out-of-band trim — same bound, same trim primitive (lib.sh's
# prune_ring) the daemon's own post-capture prune uses, so the two can't
# silently diverge on knob name or default (see this script's Env header).
cmd_prune() {
  local max_entries="${HYPR_SESSION_LOG_MAX_ENTRIES:-500}"
  if [[ ! -f $log_file ]]; then
    if [[ $JSON -eq 1 ]]; then
      jq -nc '{kept: 0, removed: 0}'
    else
      echo "No log to prune."
    fi
    return 0
  fi
  local result kept removed
  result=$(prune_ring "$log_file" "$max_entries")
  kept=${result%% *}
  removed=${result##* }
  if [[ $JSON -eq 1 ]]; then
    jq -nc --argjson kept "$kept" --argjson removed "$removed" '{kept: $kept, removed: $removed}'
  else
    echo "Pruned log: kept $kept, removed $removed"
  fi
}

subcmd="${1-}"
[[ $# -gt 0 ]] && shift

case "$subcmd" in
restore)
  [[ -x $restore_bin ]] || die "restore: sibling restore.sh not found or not executable at $restore_bin"
  exec "$restore_bin" "$@"
  ;;
list | save | rename | delete | prune)
  parse_flags "$@"
  set -- "${POSITIONAL[@]}"
  "cmd_$subcmd" "$@"
  ;;
"" | -h | --help)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
