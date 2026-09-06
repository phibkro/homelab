#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
fail() { echo "beszel agent role contract: $*" >&2; exit 1; }

[[ -f "$role_dir/defaults/main.yml" ]] || fail "defaults are missing"
[[ -f "$role_dir/tasks/main.yml" ]] || fail "tasks are missing"
[[ -f "$role_dir/handlers/main.yml" ]] || fail "handlers are missing"
[[ -f "$role_dir/templates/beszel-agent.service.j2" ]] || fail "systemd unit is missing"

rg -q '^beszel_agent_image:' "$role_dir/defaults/main.yml" || fail "image input is missing"
rg -q 'beszel_agent_image.*sha256:' "$role_dir/tasks/main.yml" || fail "immutable image assertion is missing"
rg -q 'henrygd/beszel-agent:0\.18\.8@sha256:' "$role_dir/defaults/main.yml" || fail "agent image/version is missing"
rg -q 'beszel_agent_public_key' "$role_dir/tasks/main.yml" || fail "public key input is missing"
rg -q 'ssh-\(ed25519\|rsa\|ecdsa' "$role_dir/tasks/main.yml" || fail "SSH public key validation is missing"
! rg -q 'beszel_agent_(token|hub_url)|(^|[^A-Za-z])TOKEN:|HUB_URL:' \
  "$role_dir/defaults" "$role_dir/tasks" "$role_dir/templates" "$role_dir/handlers" \
  || fail "agent must not require secret token or hub URL"
rg -q 'beszel_agent_listen_port.*45876' "$role_dir/defaults/main.yml" || fail "listener port 45876 is missing"
rg -q 'network: host' "$role_dir/tasks/main.yml" || fail "host networking is required for interface metrics"
rg -q 'beszel_agent_data_dir' "$role_dir/tasks/main.yml" || fail "agent state directory is missing"
rg -q 'no-new-privileges' "$role_dir/tasks/main.yml" || fail "hardening is missing"
rg -q 'cap_drop:' "$role_dir/tasks/main.yml" || fail "capability drop is missing"
rg -q 'read_only: true' "$role_dir/tasks/main.yml" || fail "read-only rootfs is missing"
rg -Uq '      - exec\n      - "\{\{ beszel_agent_container_name \}\}"\n      - /agent\n      - health' "$role_dir/tasks/main.yml" || fail "direct agent health verification is missing"
rg -q 'wait_for:' "$role_dir/tasks/main.yml" || fail "listener verification is missing"
rg -q '^\[Unit\]' "$role_dir/templates/beszel-agent.service.j2" || fail "systemd unit is missing"
rg -q 'podman start --attach' "$role_dir/templates/beszel-agent.service.j2" || fail "boot restore is missing"
rg -q 'Stop and disable.*disabled' "$role_dir/tasks/main.yml" || fail "disabled cleanup is missing"
echo "beszel agent role contract: PASS"
