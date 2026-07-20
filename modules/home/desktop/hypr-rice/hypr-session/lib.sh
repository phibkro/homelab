#!/usr/bin/env bash
# hypr-session-lib.sh — sourced by all four hypr-session scripts (never
# executed standalone; no shebang-driven behavior of its own). Two shared
# concerns that would otherwise silently drift if hand-duplicated per
# script (see docs/specs/2026-07-20-hypr-session-persistence-design.md):
#
#   1. state-dir default resolution — cli.sh / logd.sh / restore.sh all
#      read/write the same $HYPR_SESSION_STATE_DIR tree and used to each
#      hand-copy the same default expression.
#   2. the class -> app-specific-knowledge adapter table (design doc
#      § Restore engine — adapters: "the single home for all
#      app-specific knowledge"). capture.sh consults it for identity;
#      restore.sh consults it for launch-once-ness and match strategy.
#      Adding a class means editing the declarations below, in ONE file,
#      not four case statements spread across two scripts.
#
# Also home to prune_ring(), the ring-trim primitive logd.sh (auto,
# post-capture) and cli.sh (manual `prune` subcommand) both need — one
# trim implementation and one bound (HYPR_SESSION_LOG_MAX_ENTRIES) for
# both call sites, so the two can no longer diverge the way they once did
# (_MAX_ENTRIES vs _MAX_LINES, 500 vs 200).

hypr_session_state_dir() {
  echo "${HYPR_SESSION_STATE_DIR:-$HOME/.local/state/hypr-session}"
}

# ---- adapter table ------------------------------------------------------
# ghostty is matched by class PREFIX, not equality — kept as an explicit
# prefix test; every other class below is matched by exact equality.
adapter_is_ghostty() {
  case "$1" in
  com.mitchellh.ghostty*) return 0 ;;
  *) return 1 ;;
  esac
}

# identity_kind drives compute_identity (capture.sh): none | terminal |
# editor | media. ghostty's is prefix-matched above, not in this table.
declare -A ADAPTER_IDENTITY_KIND=(
  [code]=editor
  [vlc]=media
)
adapter_identity_kind() {
  if adapter_is_ghostty "$1"; then
    echo terminal
    return
  fi
  echo "${ADAPTER_IDENTITY_KIND[$1]:-none}"
}

# launch_once classes (restore.sh): spawn bare argv[0] ONCE, let the
# app's own session/hot-exit restore reopen its windows, then move each
# resurrected window to its captured layer per match_strategy below.
declare -A ADAPTER_LAUNCH_ONCE=(
  [code]=1
  [zen-beta]=1
)
adapter_is_launch_once() {
  [[ ${ADAPTER_LAUNCH_ONCE[$1]:-0} == 1 ]]
}

# match_strategy (restore.sh attempt_match, only consulted when
# is_launch_once): identity = match the captured identity.value against
# a live rescan; positional = no identity available for this class,
# match address order on both sides (best-effort).
declare -A ADAPTER_MATCH_STRATEGY=(
  [code]=identity
  [zen-beta]=positional
)
adapter_match_strategy() {
  echo "${ADAPTER_MATCH_STRATEGY[$1]:-positional}"
}

# Shared scan: first argv[1:] entry passing `test $test_flag arg` (-d
# dir, -f file). Used by capture.sh's editor/media identity adapters AND
# restore.sh's live-side "code" identity re-derivation, so a change to
# the heuristic (e.g. broadened to look for package.json) lands once.
adapter_first_existing_arg() {
  local test_flag=$1 cmdline_json=$2
  local arg
  while IFS= read -r arg; do
    if test "$test_flag" "$arg" 2>/dev/null; then
      printf '%s\n' "$arg"
      return 0
    fi
  done < <(jq -r '.[1:][]' <<<"$cmdline_json")
  return 1
}

# ---- ring maintenance ----------------------------------------------------
# Trims a JSONL ring file to at most $2 entries, keeping the newest.
# Prints "<kept> <removed>" on success (no-op prints "0 0"/"<total> 0").
prune_ring() {
  local file=$1 max_entries=$2
  if [[ ! -f $file ]]; then
    printf '0 0\n'
    return 0
  fi
  local total
  total=$(wc -l <"$file")
  if ((total <= max_entries)); then
    printf '%s 0\n' "$total"
    return 0
  fi
  local removed=$((total - max_entries))
  local tmp
  tmp=$(mktemp "$(dirname "$file")/.prune-ring.XXXXXX")
  tail -n "$max_entries" "$file" >"$tmp"
  mv -f "$tmp" "$file"
  printf '%s %s\n' "$max_entries" "$removed"
}
