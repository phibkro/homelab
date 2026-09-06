#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
readonly tasks_file="$role_dir/tasks/main.yml"
readonly defaults_file="$role_dir/defaults/main.yml"

fail() {
  echo "pihole role contract: $*" >&2
  exit 1
}

[[ -f "$defaults_file" ]] || fail "role defaults are missing"

for variable in pihole_lan_address pihole_tailnet_address pihole_dns_port; do
  rg -q "^${variable}:" "$defaults_file" \
    || fail "missing explicit input ${variable}"
done

rg -q 'pihole_lan_address.*pihole_dns_port.*53/tcp' "$tasks_file" \
  || fail "LAN TCP DNS publication is missing"
rg -q 'pihole_lan_address.*pihole_dns_port.*53/udp' "$tasks_file" \
  || fail "LAN UDP DNS publication is missing"
rg -q 'pihole_tailnet_address.*pihole_dns_port.*53/tcp' "$tasks_file" \
  || fail "tailnet TCP DNS publication is missing"
rg -q 'pihole_tailnet_address.*pihole_dns_port.*53/udp' "$tasks_file" \
  || fail "tailnet UDP DNS publication is missing"

if rg -q 'pihole_tailnet_address.*80/(tcp|udp)' "$tasks_file"; then
  fail "admin publication must remain LAN-only"
fi
rg -q 'pihole_lan_address.*pi_admin_port.*80/tcp' "$tasks_file" \
  || fail "LAN-only admin publication is missing"
if rg -q 'pi_service_bind_address.*pi_admin_port.*80/tcp' "$tasks_file"; then
  fail "admin publication must use the explicit Pi-hole LAN address"
fi

rg -q '^      - ip$' "$tasks_file" \
  || fail "tailnet interface readiness command is missing"
rg -q "pihole_tailnet_address ~ '/' in pihole_tailnet_interface\.stdout" "$tasks_file" \
  || fail "exact tailnet address readiness condition is missing"
rg -q 'pihole_tailnet_address != pihole_lan_address' "$tasks_file" \
  || fail "distinct LAN and tailnet address assertion is missing"
rg -q 'grep -Fq.*pihole_tailnet_address' "$role_dir/templates/podman-restart-pihole.conf.j2" \
  || fail "boot ordering must wait for the exact tailnet address"
rg -q '/usr/sbin/ip -4 -o addr show' "$role_dir/templates/podman-restart-pihole.conf.j2" \
  || fail "boot ordering must use Debian's ip path"
rg -q 'tailscaled\.service' "$role_dir/templates/podman-restart-pihole.conf.j2" \
  || fail "boot ordering must wait for tailscaled.service"

echo "pihole role contract: PASS"
