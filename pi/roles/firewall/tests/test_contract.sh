#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
template="$role_dir/templates/nftables.conf.j2"

rg -q '^delete table inet appliance_filter$' "$template" \
  || { echo 'firewall contract: appliance table is not replaced atomically' >&2; exit 1; }
rg -q 'nft.*add|appliance-owned firewall table exists' "$role_dir/tasks/main.yml" \
  || { echo 'firewall contract: scoped table bootstrap is missing' >&2; exit 1; }
rg -q 'when: not ansible_check_mode' "$role_dir/tasks/main.yml" \
  || { echo 'firewall contract: table bootstrap is unsafe in check mode' >&2; exit 1; }
rg -q 'changed_when: false' "$role_dir/tasks/main.yml" \
  || { echo 'firewall contract: idempotent table bootstrap is reported changed' >&2; exit 1; }
rg -q 'ExecStartPre=-/usr/sbin/nft add table inet appliance_filter' "$role_dir/tasks/main.yml" \
  || { echo 'firewall contract: boot-time table bootstrap is missing' >&2; exit 1; }
rg -q 'Apply appliance firewall rules without flushing Podman tables' "$role_dir/handlers/main.yml" \
  || { echo 'firewall contract: non-restarting rule application is missing' >&2; exit 1; }
if rg -q "state:.*restarted" "$role_dir/tasks/main.yml"; then
  echo 'firewall contract: restarting nftables would flush Podman networking' >&2
  exit 1
fi
if rg -q '^flush ruleset$' "$template"; then
  echo 'firewall contract: global flush would remove Podman networking' >&2
  exit 1
fi
rg -q '^table inet appliance_filter' "$template" \
  || { echo 'firewall contract: appliance filter table is missing' >&2; exit 1; }

echo 'firewall role contract: PASS'
