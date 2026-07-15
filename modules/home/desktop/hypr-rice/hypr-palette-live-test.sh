#!/usr/bin/env bash
set -euo pipefail

if [[ ${HYPR_RICE_PALETTE_LIVE_TEST:-0} != 1 ]]; then
  printf '%s\n' 'hypr-palette-live-test: set HYPR_RICE_PALETTE_LIVE_TEST=1 to run the isolated Wayland journey' >&2
  exit 64
fi

sway_bin=${SWAY_BIN:-$(command -v sway || true)}
wtype_bin=${WTYPE_BIN:-$(command -v wtype || true)}
rice_palette_bin=${RICE_PALETTE_BIN:-$(command -v rice-palette || true)}

for entry in \
  "sway:$sway_bin" \
  "wtype:$wtype_bin" \
  "rice-palette:$rice_palette_bin"; do
  name=${entry%%:*}
  path=${entry#*:}
  if [[ -z $path || ! -x $path ]]; then
    printf 'hypr-palette-live-test: %s is unavailable\n' "$name" >&2
    exit 127
  fi
done

tmp=$(mktemp -d /tmp/hp.XXXXXX)
runtime=$(mktemp -d /tmp/hr.XXXXXX)
home=$tmp/home
config_home=$tmp/config
cache_home=$tmp/cache
data_home=$tmp/data
mkdir -p "$runtime" "$home" "$config_home" "$cache_home" "$data_home/applications" "$tmp/bin"
chmod 0700 "$runtime"

sway_pid=
palette_pid=
cleanup() {
  set +e
  [[ -z $palette_pid ]] || kill "$palette_pid" 2>/dev/null
  if [[ -n $sway_pid ]]; then
    kill "$sway_pid" 2>/dev/null
    wait "$sway_pid" 2>/dev/null
  fi
  if [[ ${HYPR_PALETTE_KEEP_TMP:-0} == 1 ]]; then
    printf 'hypr-palette-live-test: preserved %s and %s\n' "$tmp" "$runtime" >&2
  else
    rm -rf "$tmp" "$runtime"
  fi
}
trap cleanup EXIT

cat >"$tmp/palette-fixture" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
env | sort >"$PALETTE_FIXTURE_ENV"
touch "$PALETTE_FIXTURE_MARKER"
EOF
chmod +x "$tmp/palette-fixture"

cat >"$tmp/bin/hypr-cheatsheet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "$PALETTE_HELP_MARKER"
EOF
chmod +x "$tmp/bin/hypr-cheatsheet"

cat >"$data_home/applications/palette-fixture.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Palette Fixture
GenericName=Palette integration fixture
Comment=Palette integration fixture
Exec=$tmp/palette-fixture
Icon=system-run
Terminal=false
EOF

cat >"$tmp/sway.conf" <<'EOF'
output * mode 1280x720
seat seat0 hide_cursor 1000
EOF

export HOME=$home
export XDG_RUNTIME_DIR=$runtime
export XDG_CONFIG_HOME=$config_home
export XDG_CACHE_HOME=$cache_home
export XDG_DATA_HOME=$data_home
export XDG_DATA_DIRS=/usr/local/share:/usr/share
export PATH="$tmp/bin:$PATH"
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS

WLR_BACKENDS=headless \
WLR_HEADLESS_OUTPUTS=1 \
WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER=gles2 \
WLR_RENDERER_ALLOW_SOFTWARE=1 \
LIBGL_ALWAYS_SOFTWARE=1 \
  "$sway_bin" --config "$tmp/sway.conf" >"$tmp/sway.log" 2>&1 &
sway_pid=$!
wayland_display=
for _ in $(seq 1 100); do
  for candidate in "$runtime"/wayland-*; do
    if [[ -S $candidate ]]; then
      wayland_display=${candidate##*/}
      break 2
    fi
  done
  kill -0 "$sway_pid" 2>/dev/null || {
    printf '%s\n' 'hypr-palette-live-test: headless Sway exited during startup' >&2
    cat "$tmp/sway.log" >&2
    exit 1
  }
  sleep 0.1
done
[[ -n $wayland_display ]]
export WAYLAND_DISPLAY=$wayland_display

export PALETTE_FIXTURE_MARKER=$tmp/fixture-ran
export PALETTE_FIXTURE_ENV=$tmp/fixture-env
"$rice_palette_bin" >"$tmp/palette-app.log" 2>&1 &
palette_pid=$!
sleep 0.5
kill -0 "$palette_pid"
"$wtype_bin" 'Palette Fixture' -k Return
wait "$palette_pid"
palette_pid=
for _ in $(seq 1 100); do
  [[ -f $PALETTE_FIXTURE_MARKER ]] && break
  sleep 0.1
done
[[ -f $PALETTE_FIXTURE_MARKER ]]
grep -Fxq 'XDG_DATA_DIRS=/usr/local/share:/usr/share' "$PALETTE_FIXTURE_ENV"
if grep -Eq '^(RICE_|DESKTOP_ENTRY_|FUZZEL_DESKTOP_FILE_ID=)' "$PALETTE_FIXTURE_ENV"; then
  printf '%s\n' 'hypr-palette-live-test: palette metadata leaked into the launched application' >&2
  exit 1
fi

export PALETTE_HELP_MARKER=$tmp/help-ran
"$rice_palette_bin" category Help >"$tmp/palette-help.log" 2>&1 &
palette_pid=$!
sleep 0.5
kill -0 "$palette_pid"
"$wtype_bin" 'Keyboard Shortcuts' -k Return
wait "$palette_pid"
palette_pid=
for _ in $(seq 1 100); do
  [[ -f $PALETTE_HELP_MARKER ]] && break
  sleep 0.1
done
[[ -f $PALETTE_HELP_MARKER ]]

printf '%s\n' 'hypr-palette-live-test: isolated application and command journeys passed'
