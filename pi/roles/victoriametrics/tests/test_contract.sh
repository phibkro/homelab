#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
fail() { echo "victoriametrics role contract: $*" >&2; exit 1; }

[[ -f "$role_dir/defaults/main.yml" ]] || fail "defaults are missing"
[[ -f "$role_dir/templates/prometheus.yml.j2" ]] || fail "scrape config template is missing"
[[ -f "$role_dir/templates/victoriametrics.service.j2" ]] || fail "systemd unit is missing"
rg -q 'victoriametrics_image.*sha256:' "$role_dir/tasks/main.yml" || fail "immutable image assertion is missing"
rg -q '^victoriametrics_image_digest: sha256:[0-9a-f]{64}$' "$role_dir/defaults/main.yml" \
  || fail "immutable image digest is missing"
rg -Fq '@{{ victoriametrics_image_digest }}' "$role_dir/defaults/main.yml" \
  || fail "image must reference the exact digest variable"
rg -q '^victoriametrics_health_address:.*victoriametrics_bind_address' "$role_dir/defaults/main.yml" \
  || fail "health probe must use the concrete published listener"
rg -q 'victoriametrics_bind_port.*8428' "$role_dir/defaults/main.yml" || fail "port 8428 is missing"
rg -q 'victoriametrics_retention_period.*14d' "$role_dir/defaults/main.yml" || fail "14-day retention is missing"
rg -q 'victoriametrics_scrape_jobs' "$role_dir/templates/prometheus.yml.j2" || fail "explicit scrape inputs are missing"
rg -q 'from_yaml' "$role_dir/tasks/main.yml" || fail "rendered config validation is missing"
rg -q 'length > 0' "$role_dir/tasks/main.yml" || fail "empty scrape config is not rejected"
rg -q "is not string" "$role_dir/tasks/main.yml" || fail "string scrape input is not rejected"
rg -Fq "reject('mapping')" "$role_dir/tasks/main.yml" || fail "non-mapping scrape jobs are not rejected"
rg -q 'static_configs' "$role_dir/tasks/main.yml" || fail "static scrape configs are not validated"
rg -q 'targets is defined' "$role_dir/tasks/main.yml" || fail "scrape targets are not validated"
rg -q 'victoriametrics_data_dir' "$role_dir/tasks/main.yml" || fail "persistent state is missing"
rg -q 'no-new-privileges' "$role_dir/tasks/main.yml" || fail "hardening is missing"
rg -q 'cap_drop:' "$role_dir/tasks/main.yml" || fail "capability drop is missing"
rg -q 'read_only: true' "$role_dir/tasks/main.yml" || fail "read-only rootfs is missing"
rg -q '^\[Unit\]' "$role_dir/templates/victoriametrics.service.j2" || fail "systemd unit is missing"
rg -q 'podman start --attach victoriametrics' "$role_dir/templates/victoriametrics.service.j2" || fail "boot restore is missing"
rg -q 'storageDataPath' "$role_dir/tasks/main.yml" || fail "explicit storage path is missing"
rg -q 'uri:' "$role_dir/tasks/main.yml" || fail "health check is missing"
echo "victoriametrics role contract: PASS"
