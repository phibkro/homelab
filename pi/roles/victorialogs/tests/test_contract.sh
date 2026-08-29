#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
fail() { echo "victorialogs role contract: $*" >&2; exit 1; }

[[ -f "$role_dir/defaults/main.yml" ]] || fail "defaults are missing"
[[ -f "$role_dir/templates/victorialogs.service.j2" ]] || fail "systemd unit is missing"
rg -q 'victorialogs_image.*sha256:' "$role_dir/tasks/main.yml" || fail "immutable image assertion is missing"
rg -q 'victorialogs_bind_port.*9428' "$role_dir/defaults/main.yml" || fail "port 9428 is missing"
rg -q 'victorialogs_retention_period.*14d' "$role_dir/defaults/main.yml" || fail "14-day retention is missing"
rg -q 'victorialogs_max_disk_usage_percent.*40' "$role_dir/defaults/main.yml" || fail "40 percent disk cap is missing"
rg -q 'victorialogs_data_dir' "$role_dir/tasks/main.yml" || fail "persistent state is missing"
rg -q 'no-new-privileges' "$role_dir/tasks/main.yml" || fail "hardening is missing"
rg -q 'cap_drop:' "$role_dir/tasks/main.yml" || fail "capability drop is missing"
rg -q 'read_only: true' "$role_dir/tasks/main.yml" || fail "read-only rootfs is missing"
rg -q '^\[Unit\]' "$role_dir/templates/victorialogs.service.j2" || fail "systemd unit is missing"
rg -q 'podman start --attach victorialogs' "$role_dir/templates/victorialogs.service.j2" || fail "boot restore is missing"
rg -q 'storageDataPath' "$role_dir/tasks/main.yml" || fail "explicit storage path is missing"
rg -q 'uri:' "$role_dir/tasks/main.yml" || fail "health check is missing"
echo "victorialogs role contract: PASS"
