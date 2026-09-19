#!/usr/bin/env bash
set -euo pipefail

if [[ ${VICINAE_LAUNCHER_LIVE_TEST:-0} != 1 ]]; then
  printf '%s\n' 'vicinae-launcher-live-test: set VICINAE_LAUNCHER_LIVE_TEST=1 to run the isolated launcher journey' >&2
  exit 64
fi

for required in RICE_VICINAE_ACTION_SCRIPTS RICE_VICINAE_EXTENSION RICE_SAVED_COMMAND_BIN RICE_NORI_DESKTOP_SETTINGS_BIN RICE_DESKTOP_COMPONENTS RICE_DESKTOP_INPUT_SCHEMA RICE_DESKTOP_OUTPUT_SCHEMA RICE_DESKTOP_RESOLVED_SETTINGS RICE_VICINAE_BIN RICE_VICINAE_TEST_SHELL; do
  if [[ -z ${!required:-} ]]; then
    printf 'vicinae-launcher-live-test: missing %s\n' "$required" >&2
    exit 64
  fi
done

tmp=$(mktemp -d)
sway_pid=
vicinae_pid=
settings_pid=
cleanup() {
  [[ -z $settings_pid ]] || kill "$settings_pid" 2>/dev/null || true
  [[ -z $vicinae_pid ]] || kill "$vicinae_pid" 2>/dev/null || true
  [[ -z $sway_pid ]] || kill "$sway_pid" 2>/dev/null || true
  wait "$settings_pid" 2>/dev/null || true
  wait "$vicinae_pid" 2>/dev/null || true
  wait "$sway_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME=$tmp/home
export XDG_CONFIG_HOME=$tmp/config
export XDG_DATA_HOME=$tmp/data
export XDG_CACHE_HOME=$tmp/cache
export XDG_STATE_HOME=$tmp/state
export XDG_RUNTIME_DIR=$tmp/runtime
mkdir -p \
  "$HOME" \
  "$XDG_CONFIG_HOME/vicinae" \
  "$XDG_DATA_HOME/vicinae/extensions/nori-desktop" \
  "$XDG_DATA_HOME/vicinae/scripts/rice" \
  "$XDG_DATA_HOME/applications" \
  "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME" \
  "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
cp -RL "$RICE_VICINAE_ACTION_SCRIPTS"/. "$XDG_DATA_HOME/vicinae/scripts/rice/"
cp -RL "$RICE_VICINAE_EXTENSION"/. "$XDG_DATA_HOME/vicinae/extensions/nori-desktop/"
mkdir -p "$XDG_DATA_HOME/nori-desktop"
cp "$RICE_DESKTOP_COMPONENTS" "$XDG_DATA_HOME/nori-desktop/components.json"
cp "$RICE_DESKTOP_INPUT_SCHEMA" "$XDG_DATA_HOME/nori-desktop/settings-input.schema.json"
cp "$RICE_DESKTOP_OUTPUT_SCHEMA" "$XDG_DATA_HOME/nori-desktop/settings-output.schema.json"
cp "$RICE_DESKTOP_RESOLVED_SETTINGS" "$XDG_DATA_HOME/nori-desktop/resolved-settings.json"
export NORI_DESKTOP_SETTINGS_CONFIG_HOME="$XDG_CONFIG_HOME/nori-desktop"
export NORI_DESKTOP_SETTINGS_STATE_HOME="$XDG_STATE_HOME/nori-desktop"
export NORI_DESKTOP_SETTINGS_DATA_DIR="$XDG_DATA_HOME/nori-desktop"
export NORI_DESKTOP_SETTINGS_RICE_COMMAND="$RICE_SAVED_COMMAND_BIN"
export NORI_DESKTOP_SETTINGS_ACTIVE_METADATA="$tmp/no-active-generation.json"
export NORI_DESKTOP_SETTINGS_SOCKET="$XDG_RUNTIME_DIR/nori-desktop/public.sock"
export NORI_DESKTOP_SETTINGS_AUTHORITY_LOCK="$XDG_RUNTIME_DIR/authority.lock"
"$RICE_NORI_DESKTOP_SETTINGS_BIN" daemon >"$tmp/settings.log" 2>&1 &
settings_pid=$!
for _ in $(seq 1 200); do
  if "$RICE_NORI_DESKTOP_SETTINGS_BIN" state --json >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
if ! "$RICE_NORI_DESKTOP_SETTINGS_BIN" state --json >/dev/null 2>&1; then
  cat "$tmp/settings.log" >&2
  exit 1
fi
printf '%s\n' '{"launcher_window":{"layer_shell":{"enabled":true}}}' \
  >"$XDG_CONFIG_HOME/vicinae/settings.json"
cat >"$XDG_DATA_HOME/applications/launcher-fixture.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Launcher Fixture Application
Exec=$RICE_VICINAE_TEST_SHELL -c true
Terminal=false
EOF

marker=$tmp/generated-command-ran
export RICE_LAUNCHER_TEST_MARKER=$tmp/generated-action-ran
jq -n \
  --arg executable "$RICE_VICINAE_TEST_SHELL" \
  --arg marker "$marker" \
  '{
    title: "Launcher round trip",
    outputMode: "silent",
    parameters: [{name: "value", optional: false}],
    execution: {
      type: "argv",
      executable: $executable,
      arguments: ["-c", "printf %s \"$1\" > \"$2\"", "rice-test", "{{value}}", $marker]
    }
  }' | "$RICE_SAVED_COMMAND_BIN" create >/dev/null

cat >"$tmp/sway.conf" <<'EOF'
output * mode 1280x720
seat seat0 hide_cursor 1000
EOF
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
sway --config "$tmp/sway.conf" >"$tmp/sway.log" 2>&1 &
sway_pid=$!

wayland_socket=
for _ in $(seq 1 100); do
  for candidate in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [[ -S $candidate ]]; then
      wayland_socket=$candidate
      break 2
    fi
  done
  sleep 0.05
done
if [[ -z $wayland_socket ]]; then
  cat "$tmp/sway.log" >&2
  exit 1
fi
export WAYLAND_DISPLAY=${wayland_socket##*/}

"$RICE_VICINAE_BIN" server --config "$XDG_CONFIG_HOME/vicinae/settings.json" \
  >"$tmp/vicinae.log" 2>&1 &
vicinae_pid=$!
for _ in $(seq 1 200); do
  if "$RICE_VICINAE_BIN" ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
if ! "$RICE_VICINAE_BIN" ping >/dev/null 2>&1; then
  cat "$tmp/vicinae.log" >&2
  exit 1
fi

commands=$tmp/commands.json
for _ in $(seq 1 200); do
  "$RICE_VICINAE_BIN" cmd ls --json >"$commands"
  if jq -e '
    any(.[]; .name == "Testing: Launcher Round Trip") and
    any(.[]; .name == "Launcher Fixture Application") and
    any(.[]; .name == "Create Command") and
    any(.[]; .name == "Launcher round trip")
  ' "$commands" >/dev/null; then
    break
  fi
  sleep 0.05
done
jq -e '
  any(.[]; .name == "Testing: Launcher Round Trip") and
  any(.[]; .name == "Launcher Fixture Application") and
  any(.[]; .name == "Create Command") and
  any(.[]; .name == "Launcher round trip")
' "$commands" >/dev/null

"$RICE_VICINAE_BIN" open
"$RICE_VICINAE_BIN" state open
action_entrypoint=$(jq -r '.[] | select(.name == "Testing: Launcher Round Trip") | .id' "$commands")
"$RICE_VICINAE_BIN" cmd launch "$action_entrypoint"
for _ in $(seq 1 100); do
  [[ ! -f $RICE_LAUNCHER_TEST_MARKER ]] || break
  sleep 0.05
done
test "$(<"$RICE_LAUNCHER_TEST_MARKER")" = 'generated action executed'


entrypoint=$(jq -r '.[] | select(.name == "Launcher round trip") | .id' "$commands")
"$RICE_VICINAE_BIN" cmd launch "$entrypoint" 'literal parameter'
for _ in $(seq 1 100); do
  [[ ! -f $marker ]] || break
  sleep 0.05
done
if [[ ! -f $marker ]]; then
  printf '%s\n' 'vicinae-launcher-live-test: saved command did not create its marker' >&2
  for generated_script in "$XDG_DATA_HOME"/vicinae/scripts/nori-saved/*.sh; do
    "$generated_script" 'diagnostic parameter' >"$tmp/generated-command.stdout" 2>"$tmp/generated-command.stderr" || true
  done
  cat "$tmp/generated-command.stderr" "$tmp/settings.log" "$tmp/vicinae.log" >&2
  exit 1
fi
test "$(<"$marker")" = 'literal parameter'

printf '%s\n' 'vicinae-launcher-live-test: isolated launcher journey passed'