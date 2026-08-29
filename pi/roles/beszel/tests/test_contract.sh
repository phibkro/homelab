#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
fail() { echo "beszel role contract: $*" >&2; exit 1; }

[[ -f "$role_dir/defaults/main.yml" ]] || fail "defaults are missing"
[[ -f "$role_dir/templates/beszel.service.j2" ]] || fail "systemd unit template is missing"
rg -q '^beszel_image:' "$role_dir/defaults/main.yml" || fail "image input is missing"
rg -q 'beszel_image.*sha256:' "$role_dir/tasks/main.yml" || fail "immutable image assertion is missing"
rg -q 'beszel_bind_port.*8090' "$role_dir/defaults/main.yml" || fail "port 8090 is missing"
rg -q '^beszel_health_address:.*beszel_bind_address' "$role_dir/defaults/main.yml" \
  || fail "health probe must use the concrete published listener"
rg -q 'beszel_data_dir' "$role_dir/tasks/main.yml" || fail "persistent state is missing"
rg -q 'no-new-privileges' "$role_dir/tasks/main.yml" || fail "hardening is missing"
rg -q 'cap_drop:' "$role_dir/tasks/main.yml" || fail "capability drop is missing"
rg -q 'read_only: true' "$role_dir/tasks/main.yml" || fail "read-only rootfs is missing"
rg -q 'healthcheck:' "$role_dir/tasks/main.yml" || fail "container healthcheck is missing"
rg -q '^\[Unit\]' "$role_dir/templates/beszel.service.j2" || fail "systemd unit is missing"
rg -q 'podman start --attach beszel' "$role_dir/templates/beszel.service.j2" || fail "boot restore is missing"
rg -q 'uri:' "$role_dir/tasks/main.yml" || fail "health check is missing"
echo "beszel role contract: PASS"
