#!/usr/bin/env bash
set -euo pipefail

role_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
defaults_file="$role_dir/defaults/main.yml"
tasks_file="$role_dir/tasks/main.yml"
service_file="$role_dir/templates/heartbeat.service.j2"
timer_file="$role_dir/templates/heartbeat.timer.j2"
helper_file="$role_dir/templates/heartbeat.sh.j2"

fail() {
  echo "heartbeat role contract: $*" >&2
  exit 1
}

for file in "$defaults_file" "$tasks_file" "$service_file" "$timer_file" "$helper_file"; do
  [[ -s "$file" ]] || fail "missing role file: $file"
done

for variable in heartbeat_enabled heartbeat_url heartbeat_secret_dir heartbeat_secret_file \
  heartbeat_on_boot_sec heartbeat_interval heartbeat_accuracy_sec heartbeat_timeout_sec \
  heartbeat_retry_count heartbeat_retry_delay_sec; do
  rg -q "^${variable}:" "$defaults_file" || fail "missing explicit input ${variable}"
done

rg -q 'healthchecks\\\\.io|hc-ping\\\\.com' "$tasks_file" \
  || fail "healthchecks host allowlist is missing"
rg -q "heartbeat_url is not search" "$tasks_file" || fail "URL newline/whitespace rejection is missing"
rg -q "heartbeat_on_boot_sec is match" "$tasks_file" || fail "timer duration validation is missing"
rg -q "heartbeat_timeout_sec is integer" "$tasks_file" || fail "numeric setting validation is missing"
rg -q 'mode: "0400"' "$tasks_file" || fail "heartbeat URL is not root-only"
rg -q 'content: "\{\{ heartbeat_url' "$tasks_file" || fail "secret URL is not installed"
rg -q 'no_log: true' "$tasks_file" || fail "secret tasks are not hidden"
rg -q 'LoadCredential=healthchecks-url:' "$service_file" || fail "systemd credential handoff is missing"
rg -q 'CREDENTIALS_DIRECTORY' "$helper_file" || fail "helper does not use transient credentials"
if rg -q 'heartbeat_url|https://hc-ping|https://healthchecks\\.io' "$service_file" "$helper_file"; then
  fail "secret or endpoint is embedded in runtime templates"
fi

for hardening in DynamicUser=true NoNewPrivileges=true PrivateTmp=true PrivateDevices=true \
  ProtectHome=true ProtectSystem=strict ProtectKernelTunables=true ProtectControlGroups=true \
  RestrictNamespaces=true RestrictRealtime=true RestrictSUIDSGID=true \
  MemoryDenyWriteExecute=true SystemCallFilter=@system-service SystemCallArchitectures=native; do
  rg -q "$hardening" "$service_file" || fail "missing service hardening: $hardening"
done
rg -q '^OnBootSec=\{\{ heartbeat_on_boot_sec \}\}$' "$timer_file" || fail "boot schedule missing"
rg -q '^OnUnitActiveSec=\{\{ heartbeat_interval \}\}$' "$timer_file" || fail "interval missing"
rg -q 'state: started' "$tasks_file" || fail "timer/live activation is missing"
rg -q 'Restart heartbeat timer after schedule changes' "$tasks_file" \
  || fail "timer schedule changes do not trigger a restart"
rg -q 'not ansible_check_mode' "$tasks_file" || fail "live validation must skip check mode"
rg -q 'systemctl.*ExecMainStatus|ExecMainStatus' "$tasks_file" || fail "status validation is missing"
rg -q 'state: absent' "$tasks_file" || fail "disabled cleanup is missing"
for path in heartbeat_timer_unit heartbeat_service_unit heartbeat_helper_path heartbeat_secret_file heartbeat_secret_dir; do
  rg -q "$path" "$tasks_file" || fail "disabled cleanup misses $path"
done

# Render and execute the real helper against a capture shim. This proves the
# URL comes from systemd's transient credential directory without contacting
# healthchecks.io (or any other network endpoint).
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/credentials"
secret_url='https://hc-ping.test/test-only-no-real-hc-id'
printf '%s\n' "$secret_url" >"$fixture_dir/credentials/healthchecks-url"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\\n" "$@" >"${HEARTBEAT_CAPTURE:?}"' \
  >"$fixture_dir/bin/curl"
chmod 0755 "$fixture_dir/bin/curl"
sed \
  -e 's|/usr/bin/curl|'"$fixture_dir"'/bin/curl|' \
  -e 's/{{ heartbeat_timeout_sec | int }}/10/' \
  -e 's/{{ heartbeat_retry_count | int }}/2/' \
  -e 's/{{ heartbeat_retry_delay_sec | int }}/5/' \
  "$helper_file" >"$fixture_dir/heartbeat"
chmod 0755 "$fixture_dir/heartbeat"
HEARTBEAT_CAPTURE="$fixture_dir/capture" \
  CREDENTIALS_DIRECTORY="$fixture_dir/credentials" \
  "$fixture_dir/heartbeat"
rg -Fxq -- "$secret_url" "$fixture_dir/capture" || fail "helper did not use credential URL"
echo "heartbeat role contract: PASS"
