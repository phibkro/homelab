#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
readonly defaults_file="$role_dir/defaults/main.yml"
readonly tasks_file="$role_dir/tasks/main.yml"
readonly template_file="$role_dir/templates/config.yaml.j2"

fail() {
  echo "gatus role contract: $*" >&2
  exit 1
}

[[ -f "$defaults_file" ]] || fail "role defaults are missing"
[[ -f "$tasks_file" ]] || fail "role tasks are missing"
[[ -f "$template_file" ]] || fail "config template is missing"

for variable in gatus_image gatus_port gatus_endpoints gatus_ntfy_token_path gatus_ntfy_environment_file; do
  rg -q "^${variable}:" "$defaults_file" \
    || fail "missing explicit input ${variable}"
done

rg -q 'twinproduction/gatus:v5\.36\.0@sha256:[0-9a-f]{64}' "$defaults_file" \
  || fail "Gatus image is not digest pinned"
rg -q 'c5f210d095fa78e6efaa20ffeb14803f2ba4f10615e16a6d12087697149617f0' "$defaults_file" \
  || fail "Gatus image must use the multiarch index digest"
rg -q 'network: host' "$tasks_file" \
  || fail "Gatus must use rootful host networking"
rg -q 'user:.*gatus_uid.*gatus_gid' "$tasks_file" \
  || fail "Gatus must run as a non-root uid/gid"
rg -q 'gatus_port.*gatus_port.*8082|gatus_bind_address.*gatus_port' "$tasks_file" \
  || fail "Gatus port publication contract is missing"
rg -q 'gatus_config_file' "$tasks_file" \
  || fail "rendered configuration path is missing"
rg -q 'gatus_ntfy_token_path' "$tasks_file" \
  || fail "ntfy token path integration is missing"
rg -q 'no_log: true' "$tasks_file" \
  || fail "secret-handling tasks must suppress logs"
rg -q 'gatus_ntfy_environment_file' "$tasks_file" \
  || fail "ntfy environment file integration is missing"
rg -q 'gatus_endpoints' "$template_file" \
  || fail "parent-supplied endpoint list is not rendered"
rg -q "endpoint\.url\.startswith\('tcp://'\)" "$template_file" \
  || fail "TCP endpoints must have protocol-aware defaults"
rg -q '^    conditions: \["\[CONNECTED\] == true"\]$' "$template_file" \
  || fail "TCP endpoints must default to the connected condition"
rg -q '^    conditions: \["\[STATUS\] == 200"\]$' "$template_file" \
  || fail "HTTP endpoints must default to the status condition"
rg -q 'endpoint\.conditions is defined and endpoint\.conditions \| length > 0' "$template_file" \
  || fail "explicit endpoint conditions must override protocol defaults"
rg -q 'storage:|gatus_storage_type' "$template_file" \
  || fail "memory-only storage contract is missing"
rg -q 'NTFY_CHANNEL' "$template_file" \
  || fail "ntfy channel environment substitution is missing"
rg -q 'NTFY_PUBLISHER_TOKEN' "$template_file" \
  || fail "ntfy token environment substitution is missing"
rg -q 'failure-threshold' "$template_file" \
  || fail "failure threshold is not rendered"
rg -q 'send-on-resolved' "$template_file" \
  || fail "resolved alert behavior is not rendered"
rg -q '/health' "$tasks_file" \
  || fail "health verification is missing"
rg -q '/metrics' "$tasks_file" \
  || fail "metrics verification is missing"
rg -q 'gatus_config_validation' "$tasks_file" \
  || fail "rendered configuration preflight is missing"
rg -q 'retries: 30' "$tasks_file" \
  || fail "health and metrics verification must retry"
rg -q 'GATUS_DELAY_START_SECONDS' "$tasks_file" \
  || fail "Gatus startup warmup must use the supported environment variable"
rg -q 'recreate:' "$tasks_file" \
  || fail "configuration changes must recreate the container"

echo "gatus role contract: PASS"
