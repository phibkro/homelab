#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
template="$role_dir/templates/nftables.conf.j2"
tmpdir="$(mktemp -d)"
readonly template tmpdir
trap 'rm -rf "$tmpdir"' EXIT

render_firewall() {
  local output="$1"
  local internet_enabled="$2"
  local variables
  variables="$(jq --compact-output --null-input \
    --argjson internet_enabled "$internet_enabled" \
    '{
      pi_lan_cidr: "192.0.2.0/24",
      pi_tailnet_interface: "tailscale0",
      pi_container_bridge_interface: "podman0",
      pihole_enabled: true,
      pi_dns_port: 53,
      pi_admin_port: 8081,
      caddy_enabled: true,
      caddy_internet_enabled: $internet_enabled,
      caddy_http_port: 80,
      caddy_https_port: 443,
      pi_tailnet_tcp_ports: [8082, 8086],
      pi_container_host_tcp_ports: [8082, 45876],
      gatus_public_enabled: true,
      gatus_public_network_interface: "gatus-public0",
      gatus_public_network_subnet: "10.89.0.0/30"
    }')"
  ansible localhost \
    --inventory localhost, \
    --connection local \
    --module-name ansible.builtin.template \
    --args "src=$template dest=$output mode=0600" \
    --extra-vars "$variables" >/dev/null
}

require_line() {
  local line="$1"
  local file="$2"
  rg --fixed-strings --line-regexp --quiet "$line" "$file" \
    || { printf 'firewall contract: missing rule: %s\n' "$line" >&2; exit 1; }
}

reject_line() {
  local line="$1"
  local file="$2"
  if rg --fixed-strings --line-regexp --quiet "$line" "$file"; then
    printf 'firewall contract: forbidden rule: %s\n' "$line" >&2
    exit 1
  fi
}

public_rules="$tmpdir/public.nft"
internal_rules="$tmpdir/internal.nft"
render_firewall "$public_rules" true
render_firewall "$internal_rules" false

require_line 'delete table inet appliance_filter' "$public_rules"
require_line '    type filter hook input priority filter; policy drop;' "$public_rules"
reject_line 'flush ruleset' "$public_rules"

require_line '    ip saddr 192.0.2.0/24 tcp dport 80 accept' "$public_rules"
require_line '    tcp dport 443 accept' "$public_rules"
require_line '    iifname "tailscale0" tcp dport 80 accept' "$public_rules"
reject_line '    tcp dport 80 accept' "$public_rules"
reject_line '    ip saddr 192.0.2.0/24 tcp dport 443 accept' "$public_rules"
reject_line '    iifname "tailscale0" tcp dport 443 accept' "$public_rules"
require_line '    iifname "gatus-public0" tcp dport 443 accept' "$public_rules"
require_line '    ip saddr 10.89.0.0/30 drop' "$public_rules"
require_line '    ct state established,related accept' "$public_rules"

reject_line '    tcp dport 443 accept' "$internal_rules"
require_line '    ip saddr 192.0.2.0/24 tcp dport 443 accept' "$internal_rules"
require_line '    iifname "tailscale0" tcp dport 443 accept' "$internal_rules"
require_line '    ip saddr 10.89.0.0/30 drop' "$internal_rules"

echo 'firewall render contract: PASS'
