#!/usr/bin/env bats
# Red-green tests for cli.sh — session management (list/save/rename/delete/
# prune) plus the `restore` delegation seam.
# Requires: bats, jq (nix shell nixpkgs#bats nixpkgs#jq -c bats tests/cli.bats)

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  cli=$script_dir/../cli.sh
  state_dir=$(mktemp -d)
  export HYPR_SESSION_STATE_DIR=$state_dir
  # cli.sh must never touch the real compositor directly (it only
  # delegates `restore` to a sibling script) — point this at an isolated
  # value so a bug that DID reach for hyprctl would be obvious.
  export HYPRLAND_INSTANCE_SIGNATURE=bats-isolated-instance
}

teardown() {
  rm -rf "$state_dir"
  [[ -n ${extra_dirs+set} ]] && rm -rf "${extra_dirs[@]}"
  true
}

# A full v1 snapshot skeleton with caller-supplied windows, used as
# current.json — real values (real schema shape), not a stub of the
# capture contract.
write_current() {
  local windows_json="$1"
  jq -n --argjson windows "$windows_json" '{
    version: 1,
    captured_at: "2026-07-20T09:00:00Z",
    monitors: [{id: 0, name: "DP-3", width: 3440, height: 1440}],
    focus: {focused_window: null, monitors: [{monitor: "DP-3", active_workspace: "1", special_workspace: null}]},
    windows: $windows
  }' >"$state_dir/current.json"
}

@test "list --json on empty state emits empty named list and null last" {
  run bash "$cli" list --json
  [ "$status" -eq 0 ]
  named_count=$(jq '.named | length' <<<"$output")
  [ "$named_count" = "0" ]
  last=$(jq '.last' <<<"$output")
  [ "$last" = "null" ]
}

@test "list human output reports no sessions on empty state" {
  run bash "$cli" list
  [ "$status" -eq 0 ]
  [[ $output == *"No sessions"* ]]
}

@test "save fails loudly when there is no current session to freeze" {
  run bash "$cli" save morning
  [ "$status" -ne 0 ]
  [[ $output == *current.json* ]]
}

@test "save freezes current.json into named/<name>.json as a RAW v1 snapshot with label/created_at embedded, directly restorable by restore.sh" {
  write_current '[]'
  run bash "$cli" save morning
  [ "$status" -eq 0 ]
  [ -f "$state_dir/named/morning.json" ]
  label=$(jq -r '.label' "$state_dir/named/morning.json")
  [ "$label" = "morning" ]
  created_at=$(jq -r '.created_at' "$state_dir/named/morning.json")
  [[ $created_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  # schema seam: restore.sh reads named/<name>.json expecting a raw v1
  # snapshot at the top level ($(jq -r '.version') == "1"), the same
  # shape as current.json — NOT wrapped under a .snapshot key. A wrapper
  # here is exactly the save/restore mismatch that broke every named
  # restore (docs/specs/2026-07-20-hypr-session-persistence-design.md).
  version=$(jq -r '.version' "$state_dir/named/morning.json")
  [ "$version" = "1" ]
  has_snapshot_key=$(jq 'has("snapshot")' "$state_dir/named/morning.json")
  [ "$has_snapshot_key" = "false" ]
  windows=$(jq -r '.windows' "$state_dir/named/morning.json")
  [ "$windows" = "[]" ]
}

@test "save refuses to clobber an existing named session" {
  write_current '[]'
  bash "$cli" save morning
  run bash "$cli" save morning
  [ "$status" -ne 0 ]
  [[ $output == *morning* ]]
}

@test "list --json surfaces a saved named session with its label and created_at" {
  write_current '[]'
  bash "$cli" save morning
  run bash "$cli" list --json
  [ "$status" -eq 0 ]
  name=$(jq -r '.named[0].name' <<<"$output")
  [ "$name" = "morning" ]
  label=$(jq -r '.named[0].label' <<<"$output")
  [ "$label" = "morning" ]
  created_at=$(jq -r '.named[0].created_at' <<<"$output")
  [[ $created_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "list --json derives the last head's auto-label from the dominant window identity" {
  write_current '[
    {"address": "0x1", "class": "code", "title": "a", "workspace": "1", "floating": false, "geometry": null,
     "process": {"cwd": "/home/nori/projects/foo", "cmdline": ["code", "/home/nori/projects/foo"]},
     "identity": {"kind": "editor", "value": "/home/nori/projects/foo"}},
    {"address": "0x2", "class": "com.mitchellh.ghostty", "title": "b", "workspace": "1", "floating": false, "geometry": null,
     "process": {"cwd": "/home/nori/projects/foo", "cmdline": ["ghostty"]},
     "identity": {"kind": "terminal", "value": "/home/nori/projects/foo"}},
    {"address": "0x3", "class": "vlc", "title": "c", "workspace": "1", "floating": false, "geometry": null,
     "process": {"cwd": "/tmp", "cmdline": ["vlc", "/tmp/other.mp4"]},
     "identity": {"kind": "media", "value": "/tmp/other.mp4"}}
  ]'
  run bash "$cli" list --json
  [ "$status" -eq 0 ]
  last_label=$(jq -r '.last.label' <<<"$output")
  [ "$last_label" = "foo" ]
  last_captured_at=$(jq -r '.last.captured_at' <<<"$output")
  [ "$last_captured_at" = "2026-07-20T09:00:00Z" ]
}

@test "list --json falls back to a generic label when no window carries an identity" {
  write_current '[
    {"address": "0x1", "class": "firefox", "title": "a", "workspace": "1", "floating": false, "geometry": null,
     "process": null, "identity": null}
  ]'
  run bash "$cli" list --json
  [ "$status" -eq 0 ]
  last_label=$(jq -r '.last.label' <<<"$output")
  [ "$last_label" = "session" ]
}

@test "rename moves a named session and updates its embedded label" {
  write_current '[]'
  bash "$cli" save morning
  run bash "$cli" rename morning renamed
  [ "$status" -eq 0 ]
  [ ! -f "$state_dir/named/morning.json" ]
  [ -f "$state_dir/named/renamed.json" ]
  label=$(jq -r '.label' "$state_dir/named/renamed.json")
  [ "$label" = "renamed" ]
}

@test "rename fails loudly when the source session doesn't exist" {
  run bash "$cli" rename ghost renamed
  [ "$status" -ne 0 ]
  [[ $output == *ghost* ]]
}

@test "rename refuses to clobber an existing target session" {
  write_current '[]'
  bash "$cli" save morning
  bash "$cli" save evening
  run bash "$cli" rename morning evening
  [ "$status" -ne 0 ]
  [[ $output == *evening* ]]
  # source must survive an aborted rename
  [ -f "$state_dir/named/morning.json" ]
}

@test "delete removes a named session" {
  write_current '[]'
  bash "$cli" save morning
  run bash "$cli" delete morning
  [ "$status" -eq 0 ]
  [ ! -f "$state_dir/named/morning.json" ]
}

@test "delete fails loudly when the session doesn't exist" {
  run bash "$cli" delete ghost
  [ "$status" -ne 0 ]
  [[ $output == *ghost* ]]
}

@test "prune is a no-op when log.jsonl doesn't exist" {
  run bash "$cli" prune --json
  [ "$status" -eq 0 ]
  kept=$(jq '.kept' <<<"$output")
  [ "$kept" = "0" ]
}

@test "prune trims log.jsonl to the ring bound, keeping only the newest entries" {
  for i in $(seq 1 10); do
    printf '{"n": %d}\n' "$i" >>"$state_dir/log.jsonl"
  done
  run env HYPR_SESSION_LOG_MAX_ENTRIES=3 bash "$cli" prune --json
  [ "$status" -eq 0 ]
  kept=$(jq '.kept' <<<"$output")
  [ "$kept" = "3" ]
  removed=$(jq '.removed' <<<"$output")
  [ "$removed" = "7" ]
  line_count=$(wc -l <"$state_dir/log.jsonl")
  [ "$line_count" = "3" ]
  # newest (highest n) entries survive, oldest are dropped
  last_n=$(jq -s '.[-1].n' "$state_dir/log.jsonl")
  [ "$last_n" = "10" ]
  first_n=$(jq -s '.[0].n' "$state_dir/log.jsonl")
  [ "$first_n" = "8" ]
}

@test "unknown subcommand exits nonzero with usage on stderr" {
  run bash "$cli" bogus-subcommand
  [ "$status" -ne 0 ]
  [[ $output == *"usage"* || $output == *"Usage"* ]]
}

@test "restore delegates its argv (minus the subcommand word) to the sibling restore.sh" {
  extra_tmp=$(mktemp -d)
  extra_dirs=("$extra_tmp")
  cp "$cli" "$extra_tmp/cli.sh"
  cp "$script_dir/../lib.sh" "$extra_tmp/lib.sh"
  cat >"$extra_tmp/restore.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname "$0")/argv.log"
EOF
  chmod +x "$extra_tmp/restore.sh"

  run bash "$extra_tmp/cli.sh" restore morning --diff
  [ "$status" -eq 0 ]
  [ -f "$extra_tmp/argv.log" ]
  run cat "$extra_tmp/argv.log"
  [ "${lines[0]}" = "morning" ]
  [ "${lines[1]}" = "--diff" ]
}

@test "restore fails loudly when the sibling restore.sh is missing" {
  extra_tmp=$(mktemp -d)
  extra_dirs=("$extra_tmp")
  cp "$cli" "$extra_tmp/cli.sh"
  cp "$script_dir/../lib.sh" "$extra_tmp/lib.sh"

  run bash "$extra_tmp/cli.sh" restore morning
  [ "$status" -ne 0 ]
  [[ $output == *restore.sh* ]]
}
