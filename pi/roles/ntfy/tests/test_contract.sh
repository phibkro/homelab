#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
readonly defaults_file="$role_dir/defaults/main.yml"
readonly tasks_file="$role_dir/tasks/main.yml"
readonly env_template="$role_dir/templates/ntfy.env.j2"
readonly alert_config_template="$role_dir/templates/ntfy-alert.env.j2"
readonly alert_template="$role_dir/templates/nori-alert.j2"
readonly notify_template="$role_dir/templates/notify@.service.j2"
readonly notify_helper="$role_dir/templates/ntfy-notify.j2"

fail() {
  echo "ntfy role contract: $*" >&2
  exit 1
}

for file in "$defaults_file" "$tasks_file" "$env_template" "$alert_config_template" "$alert_template" \
  "$notify_template" "$notify_helper"; do
  [[ -f "$file" ]] || fail "missing role file: $file"
done

for variable in ntfy_image ntfy_bind_address ntfy_port ntfy_publisher_token \
  ntfy_publisher_password_hash ntfy_agents_channel ntfy_alert_url \
  ntfy_operator_topic_file ntfy_agents_topic_file ntfy_alert_routes; do
  rg -q "^${variable}:" "$defaults_file" \
    || fail "missing explicit input ${variable}"
done

rg -q 'docker\.io/binwiederhier/ntfy:v2\.27\.0@sha256:[0-9a-f]{64}' "$defaults_file" \
  || fail "ntfy image is not pinned to a full manifest digest"
rg -q '^ntfy_port: 8091$' "$defaults_file" \
  || fail "ntfy must use the port reserved beside Pi-hole's temporary 8081"
rg -Fq "      - ntfy_publisher_token is match('^tk_[A-Za-z0-9]{29}$')" "$tasks_file" \
  || fail "publisher token must use ntfy's 32-character tk_ format"
if ! rg -Fq "ntfy_publisher_password_hash is match" "$tasks_file" \
  || ! rg -Fq '\$2[aby]\$' "$tasks_file"; then
  fail "publisher password must be a bcrypt hash"
fi

rg -q 'NTFY_AUTH_DEFAULT_ACCESS=.*ntfy_auth_default_access' "$env_template" \
  || fail "auth default access is not rendered"
rg -q '^ntfy_auth_default_access: deny-all$' "$defaults_file" \
  || fail "ntfy auth must use the upstream deny-all policy"
rg -q '^ntfy_enable_anonymous_read: false$' "$defaults_file" \
  || fail "anonymous read must be opt-in"
rg -q 'url: https://ntfy\.sh' "$defaults_file" \
  || fail "operator route must remain on public ntfy.sh"
rg -q 'token_file: ""' "$defaults_file" \
  || fail "operator route must not require the local publisher token"
rg -Fq "      - ntfy_alert_routes.operator.topic is match('^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$')" "$tasks_file" \
  || fail "operator topic does not use the safe topic-name contract"
rg -q 'NTFY_AUTH_USERS=.*ntfy_publisher_password_hash' "$env_template" \
  || fail "publisher user bootstrap is missing"
rg -q 'NTFY_AUTH_TOKENS=.*ntfy_publisher_token' "$env_template" \
  || fail "publisher token bootstrap is missing"
rg -q '\{% if ntfy_enable_anonymous_read %\}' "$env_template" \
  || fail "anonymous read ACL is not conditional"
rg -q 'NTFY_AUTH_ACCESS=everyone:.*ntfy_agents_channel.*:ro' "$env_template" \
  || fail "scoped anonymous read grant is missing from opt-in branch"

if rg -q '^NTFY_AUTH_ACCESS=' <(awk '/\{% if ntfy_enable_anonymous_read %\}/{skip=1; next} /\{% endif %\}/{skip=0; next} !skip' "$env_template"); then
  fail "anonymous read ACL is unconditional"
fi

render_env() {
  local enabled="$1"
  local output="$2"
  awk -v enabled="$enabled" '
    index($0, "{% if ntfy_enable_anonymous_read %}") { skip=1; next }
    index($0, "{% endif %}") { skip=0; next }
    !skip || enabled == "true" { print }
  ' "$env_template" \
    | sed \
      -e 's/{{ ntfy_base_url }}/https:\/\/alert.example.test/g' \
      -e 's/{{ ntfy_auth_default_access }}/deny-all/g' \
      -e 's/{{ ntfy_enable_login | ternary('\''true'\'', '\''false'\'') }}/true/g' \
      -e 's/{{ ntfy_behind_proxy | ternary('\''true'\'', '\''false'\'') }}/false/g' \
      -e 's/{{ ntfy_publisher_username }}/publisher/g' \
      -e 's/{{ ntfy_publisher_password_hash }}/\$2b\$12\$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g' \
      -e 's/{{ ntfy_publisher_token }}/tk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g' \
      -e 's/{{ ntfy_agents_channel }}/agents-topic/g' \
      -e 's/{{ ntfy_timezone }}/Europe\/Oslo/g' > "$output"
}

fixture_env_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_env_dir"' EXIT
render_env false "$fixture_env_dir/anonymous-read-false.env"
render_env true "$fixture_env_dir/anonymous-read-true.env"
if rg -q '^NTFY_AUTH_ACCESS=' "$fixture_env_dir/anonymous-read-false.env"; then
  fail "false anonymous-read setting still rendered an ACL"
fi
rg -q '^NTFY_AUTH_ACCESS=everyone:agents-topic:ro$' "$fixture_env_dir/anonymous-read-true.env" \
  || fail "true anonymous-read setting did not render the scoped ACL"

rg -q 'env_file:' "$tasks_file" || fail "root-only env file is not passed to Podman"
rg -q 'restart_policy: always' "$tasks_file" || fail "restart policy is missing"
rg -q 'read_only: true' "$tasks_file" || fail "container filesystem is not read-only"
rg -q 'cap_drop:' "$tasks_file" || fail "container capabilities are not dropped"
rg -q 'no-new-privileges:true' "$tasks_file" || fail "no-new-privileges is missing"
rg -q 'ntfy_cache_dir.*:/var/cache/ntfy' "$tasks_file" || fail "cache volume is not persistent"
rg -q 'ntfy_state_dir.*:/var/lib/ntfy' "$tasks_file" || fail "auth/state volume is not persistent"
rg -q 'ntfy_bind_address.*ntfy_port.*80/tcp' "$tasks_file" || fail "host port publication is missing"
rg -q '/v1/health' "$tasks_file" || fail "health endpoint check is missing"
rg -q 'ntfy_image_pull\.changed' "$tasks_file" \
  || fail "image pull changes must recreate the container"
rg -q 'Remove role-owned ntfy files when explicitly disabled' "$tasks_file" \
  || fail "disabled-state cleanup is missing"
for path in 'ntfy_publisher_token_file' 'ntfy_operator_topic_file' \
  'ntfy_agents_topic_file' '/usr/local/libexec/nori-alert' \
  '/etc/systemd/system/notify@.service'; do
  rg -q "$path" "$tasks_file" || fail "disabled cleanup misses $path"
done
if rg -q 'ntfy_(cache|state)_dir.*state: absent' "$tasks_file"; then
  fail "disabling ntfy must preserve persistent cache and state"
fi

rg -q 'Authorization: Bearer' "$alert_template" || fail "nori-alert auth header is missing"
rg -q 'token_file' "$alert_template" || fail "nori-alert must read the token at send time"
rg -q 'NTFY_ALERT_ROUTE_OPERATOR_URL=.*ntfy_alert_routes\.operator\.url' "$alert_config_template" \
  || fail "operator route is not rendered from explicit inputs"
rg -q 'NTFY_ALERT_ROUTE_AGENTS_URL=.*ntfy_alert_routes\.agents\.url' "$alert_config_template" \
  || fail "agents route is not rendered from explicit inputs"
rg -q 'operator\)' "$alert_template" || fail "operator audience route is missing"
rg -q 'agents\)' "$alert_template" || fail "agents audience route is missing"
rg -q 'if \[\[ -n "\$token_file" \]\]' "$alert_template" \
  || fail "bearer authentication must be conditional per route"
rg -q 'printf -v alert_body' "$notify_helper" \
  || fail "notify helper must construct a body with real newlines"
if rg -q -- '--body ".*\\n' "$notify_helper"; then
  fail "notify helper passes literal backslash-n sequences"
fi
rg -q 'ExecStart=/usr/local/libexec/ntfy-notify %i' "$notify_template" \
  || fail "notify@ template is not wired"
rg -q 'systemctl is-failed' "$notify_helper" || fail "notify helper lacks persistent-failure gate"

# When pointed at a live test instance, verify the security contract end to end:
# anonymous publish is rejected while a configured publisher token succeeds.
if [[ -n "${NTFY_TEST_URL:-}" ]]; then
  : "${NTFY_TEST_TOPIC:?NTFY_TEST_TOPIC is required with NTFY_TEST_URL}"
  : "${NTFY_TEST_TOKEN:?NTFY_TEST_TOKEN is required with NTFY_TEST_URL}"
  test_url="${NTFY_TEST_URL%/}/${NTFY_TEST_TOPIC}"
  anonymous_status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    --data-binary 'anonymous-publish-contract' "$test_url")"
  [[ "$anonymous_status" == 401 || "$anonymous_status" == 403 ]] \
    || fail "anonymous publish returned HTTP $anonymous_status"
  authenticated_status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer ${NTFY_TEST_TOKEN}" \
    --data-binary 'authenticated-publish-contract' "$test_url")"
  [[ "$authenticated_status" == 200 ]] \
    || fail "authenticated publish returned HTTP $authenticated_status"
fi

# Render the route configuration into a temporary fixture and execute the
# real nori-alert shell template against a curl capture shim. This exercises
# that operator has no bearer header while agents load the token file and use
# the local endpoint.
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"
printf '%s\n' 'operator-topic' > "$fixture_dir/operator-topic"
printf '%s\n' 'agents-topic' > "$fixture_dir/agents-topic"
printf '%s\n' 'tk_test_123456789012345678901234567' > "$fixture_dir/publisher-token"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\\n" "$@" > "$NTFY_CURL_CAPTURE"' \
  > "$fixture_dir/bin/curl"
chmod +x "$fixture_dir/bin/curl"
printf '%s\n' \
  "NTFY_ALERT_ROUTE_OPERATOR_URL=https://ntfy.sh" \
  "NTFY_ALERT_ROUTE_OPERATOR_TOPIC_FILE=$fixture_dir/operator-topic" \
  "NTFY_ALERT_ROUTE_OPERATOR_TOKEN_FILE=" \
  "NTFY_ALERT_ROUTE_AGENTS_URL=http://127.0.0.1:8091" \
  "NTFY_ALERT_ROUTE_AGENTS_TOPIC_FILE=$fixture_dir/agents-topic" \
  "NTFY_ALERT_ROUTE_AGENTS_TOKEN_FILE=$fixture_dir/publisher-token" \
  > "$fixture_dir/alert.env"
sed "s|readonly config_file=/etc/default/ntfy-alert|readonly config_file=$fixture_dir/alert.env|" \
  "$alert_template" > "$fixture_dir/nori-alert"
chmod +x "$fixture_dir/nori-alert"

NTFY_CURL_CAPTURE="$fixture_dir/operator-curl" PATH="$fixture_dir/bin:$PATH" \
  bash "$fixture_dir/nori-alert" --audience operator --severity urgent \
  --title operator-test --body operator-body
rg -Fxq 'https://ntfy.sh/operator-topic' "$fixture_dir/operator-curl" \
  || fail "operator route did not target ntfy.sh"
if rg -q 'Authorization: Bearer' "$fixture_dir/operator-curl"; then
  fail "operator route unexpectedly sent the local bearer token"
fi

NTFY_CURL_CAPTURE="$fixture_dir/agents-curl" PATH="$fixture_dir/bin:$PATH" \
  bash "$fixture_dir/nori-alert" --audience agents --severity info \
  --title agents-test --body agents-body
rg -Fxq 'http://127.0.0.1:8091/agents-topic' "$fixture_dir/agents-curl" \
  || fail "agents route did not target the local ntfy endpoint"
rg -Fxq 'Authorization: Bearer tk_test_123456789012345678901234567' \
  "$fixture_dir/agents-curl" \
  || fail "agents route did not load the publisher token file"

# The notify helper must pass actual newlines to nori-alert, not a literal
# two-character backslash-n sequence.
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1" == "is-failed" ]]; then exit 0; fi' \
  > "$fixture_dir/bin/systemctl"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" journal-line' \
  > "$fixture_dir/bin/journalctl"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" test-host' \
  > "$fixture_dir/bin/hostname"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\\n" "$@" > "$NTFY_ALERT_CAPTURE"' \
  > "$fixture_dir/capture-alert"
chmod +x "$fixture_dir/bin/systemctl" "$fixture_dir/bin/journalctl" \
  "$fixture_dir/bin/hostname" "$fixture_dir/capture-alert"
sed "s|/usr/local/libexec/nori-alert|$fixture_dir/capture-alert|" \
  "$notify_helper" > "$fixture_dir/ntfy-notify"
chmod +x "$fixture_dir/ntfy-notify"
NTFY_ALERT_CAPTURE="$fixture_dir/notify-capture" PATH="$fixture_dir/bin:$PATH" \
  bash "$fixture_dir/ntfy-notify" failed.service
if rg -Fq '\\n' "$fixture_dir/notify-capture"; then
  fail "notify helper emitted a literal backslash-n"
fi
rg -q 'Recent journal:' "$fixture_dir/notify-capture" \
  || fail "notify helper omitted journal context"

echo "ntfy role contract: PASS"
