{
  pkgs,
  detectorScript,
}:

let
  fakeSystemctl = pkgs.writeShellScript "steady-state-resource-alert-fake-systemctl" ''
    unit="$3"
    property="$5"
    if [ "$unit" != waybar.service ]; then
      [ "$property" = ActiveState ] && printf '%s\n' inactive
      exit 0
    fi

    case "$property" in
      ActiveState) printf '%s\n' active ;;
      InvocationID) printf '%s\n' test-invocation ;;
      ControlGroup) printf '%s\n' /waybar ;;
    esac
  '';

  fakeAlert = pkgs.writeShellScript "steady-state-resource-alert-fake-alert" ''
    touch "$ALERT_MARKER"
  '';
in
pkgs.runCommandLocal "steady-state-resource-alert-working-set" { } ''
  set -eu

  fixture="$TMPDIR/fixture"
  mkdir -p "$fixture/bin" "$fixture/cgroup/waybar" "$fixture/state"
  ln -s ${fakeSystemctl} "$fixture/bin/systemctl"

  printf '%s\n' 220200960 > "$fixture/cgroup/waybar/memory.current"
  printf '%s\n' 0 > "$fixture/cgroup/waybar/memory.swap.current"
  printf '%s\n' \
    'anon 10485760' \
    'inactive_file 209715200' \
    'active_file 0' \
    > "$fixture/cgroup/waybar/memory.stat"
  printf '%s\n' 0 > "$fixture/cgroup/waybar/pids.current"
  : > "$fixture/cgroup/waybar/cgroup.procs"

  # A raw memory.current calculation would report a third consecutive
  # 200 MiB breach. The working set is unchanged at 10 MiB because all
  # growth is inactive file cache left in the service cgroup.
  printf '%s\n' 'test-invocation 1 10485760 0 0 2 0' \
    > "$fixture/state/waybar.state"

  output="$(
    PATH="$fixture/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin" \
    STATE_DIRECTORY="$fixture/state" \
    RESOURCE_EFFICIENCY_CGROUP_ROOT="$fixture/cgroup" \
    RESOURCE_EFFICIENCY_ALERT_COMMAND=${fakeAlert} \
    ALERT_MARKER="$fixture/alerted" \
    ${detectorScript} 2>&1
  )"

  case "$output" in
    *'target=waybar'*'phase=steady'*'footprint_bytes=10485760'*'breach=0'*'streak=0'*) ;;
    *)
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
  test ! -e "$fixture/alerted"
  touch "$out"
''
