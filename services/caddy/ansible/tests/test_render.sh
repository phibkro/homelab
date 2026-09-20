#!/usr/bin/env bash
set -euo pipefail

for command in ansible-playbook caddy jq nix; do
  if ! command -v "$command" >/dev/null; then
    echo "caddy render contract: SKIP ($command is required in the Pi dev shell)"
    exit 0
  fi
done

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$role_dir/../../.." && pwd)"
readonly repo_root

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

cat >"$state_dir/vars.yml" <<EOF
caddy_template: "$role_dir/templates/Caddyfile.j2"
caddy_output: "$state_dir/Caddyfile"
caddy_acme_email: test@example.invalid
caddy_http_port: 80
caddy_https_port: 443
caddy_tls_mode: internal
pi_domain: test.lan
pi_deprecated_domains:
  - nori.lan
pi_service_bind_address: 192.168.1.225
pi_routes:
  - name: pihole
    hostname: pihole.test.lan
    upstream_address: 192.168.1.225
    upstream_port: 8081
    scheme: http
    reachability: internal
    audience: operator
    auth: none
    forward_auth_exempt_paths: []
    forward_auth_upstream: null
    upstream_host_header: null
    upstream_origin_header: null
  - name: auth
    hostname: auth.test.lan
    upstream_address: 192.168.1.225
    upstream_port: 9091
    scheme: http
    reachability: internal
    audience: public
    auth: none
    forward_auth_exempt_paths: []
    forward_auth_upstream: null
    upstream_host_header: null
    upstream_origin_header: null

  - name: books
    hostname: books.test.lan
    upstream_address: 100.81.5.122
    upstream_port: 8084
    scheme: http
    reachability: internal
    audience: family
    auth: forward-auth
    forward_auth_exempt_paths:
      - /api/*
    forward_auth_upstream: 192.168.1.225:9091
    upstream_host_header: null
    upstream_origin_header: null
  - name: secure
    hostname: secure.test.lan
    upstream_address: 100.81.5.122
    upstream_port: 9443
    scheme: https
    reachability: internet
    audience: family
    auth: none
    forward_auth_exempt_paths: []
    forward_auth_upstream: 192.168.1.225:9091
    upstream_host_header: secure.backend.lan
    upstream_origin_header: https://secure.backend.lan
authelia_oidc_clients: []

EOF

cat >"$state_dir/playbook.yml" <<EOF
---
- name: Render Caddy contract fixture
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - "$repo_root/infra/pi/playbooks/group_vars/all.yml"
    - "$state_dir/vars.yml"
  tasks:
    - name: Render Caddyfile
      ansible.builtin.template:
        src: "{{ caddy_template }}"
        dest: "{{ caddy_output }}"
EOF

ansible-playbook -i localhost, "$state_dir/playbook.yml" >/dev/null

rg -q '^http://\*\.nori\.lan \{' "$state_dir/Caddyfile"
rg -q 'redir @legacySubdomain https://\{re\.legacySubdomain\.1\}\.test\.lan\{uri\} 301' "$state_dir/Caddyfile"
rg -q 'forward_auth @booksAuthNeeded http://192\.168\.1\.225:9091' "$state_dir/Caddyfile"
rg -q 'not path /api/\*' "$state_dir/Caddyfile"
rg -q 'uri /api/verify\?rd=https://auth\.test\.lan' "$state_dir/Caddyfile"
rg -q 'reverse_proxy https://100\.81\.5\.122:9443' "$state_dir/Caddyfile"
rg -q 'header_up Host secure\.backend\.lan' "$state_dir/Caddyfile"
rg -q 'header_up Origin https://secure\.backend\.lan' "$state_dir/Caddyfile"

caddy adapt --config "$state_dir/Caddyfile" --adapter caddyfile >/dev/null
caddy validate --config "$state_dir/Caddyfile" --adapter caddyfile >/dev/null

# Exercise the real compiler boundary as well as the focused fixture above.
"$repo_root/infra/pi/scripts/generate-inventory.sh" "$state_dir/inventory.json" >/dev/null
jq '.pi_appliances.hosts.pi' "$state_dir/inventory.json" >"$state_dir/inventory-vars.json"
cat >"$state_dir/production-playbook.yml" <<EOF
---
- name: Render Caddy from the compiler projection
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - "$repo_root/infra/pi/playbooks/group_vars/all.yml"
    - "$state_dir/inventory-vars.json"
  vars:
    caddy_template: "$role_dir/templates/Caddyfile.j2"
    caddy_output: "$state_dir/ProductionCaddyfile"
    caddy_acme_email: test@example.invalid
    pi_emulation_mode: true
    caddy_tls_mode: internal
  tasks:
    - name: Render Caddyfile
      ansible.builtin.template:
        src: "{{ caddy_template }}"
        dest: "{{ caddy_output }}"
EOF
ansible-playbook -i localhost, "$state_dir/production-playbook.yml"
caddy adapt --config "$state_dir/ProductionCaddyfile" --adapter caddyfile >/dev/null
caddy validate --config "$state_dir/ProductionCaddyfile" --adapter caddyfile >/dev/null
while IFS= read -r hostname; do
  rg -Fq "host $hostname" "$state_dir/ProductionCaddyfile"
done < <(jq -r '.pi_appliances.hosts.pi.pi_routes[].hostname' "$state_dir/inventory.json")

echo "caddy render contract: PASS"
