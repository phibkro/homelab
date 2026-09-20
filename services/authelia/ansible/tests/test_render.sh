#!/usr/bin/env bash
set -euo pipefail

for command in ansible-playbook jq rg; do
  if ! command -v "$command" >/dev/null; then
    echo "authelia render contract: SKIP ($command is required in the Pi dev shell)"
    exit 0
  fi
done

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$role_dir/../../.." && pwd)"
state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

"$repo_root/infra/pi/scripts/generate-inventory.sh" "$state_dir/inventory.json" >/dev/null
jq '.pi_appliances.hosts.pi' "$state_dir/inventory.json" >"$state_dir/inventory-vars.json"

cat >"$state_dir/playbook.yml" <<EOF
---
- name: Render Authelia configuration from the compiler projection
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - "$role_dir/defaults/main.yml"
    - "$state_dir/inventory-vars.json"
  vars:
    authelia_template: "$role_dir/templates/configuration.yml.j2"
    authelia_output: "$state_dir/configuration.yml"
  tasks:
    - name: Render Authelia configuration
      ansible.builtin.template:
        src: "{{ authelia_template }}"
        dest: "{{ authelia_output }}"
EOF

ansible-playbook -i localhost, "$state_dir/playbook.yml" >/dev/null

expected_count="$(jq '.pi_appliances.hosts.pi.authelia_oidc_clients | length' "$state_dir/inventory.json")"
actual_count="$(rg -c '^      - client_id:' "$state_dir/configuration.yml")"
[[ "$actual_count" == "$expected_count" ]]

while IFS= read -r client_id; do
  rg -Fq "      - client_id: \"$client_id\"" "$state_dir/configuration.yml"
  rg -Fq "client_secret: {{ secret \"/run/secrets/oidc-$client_id-client-secret-hash\" }}" \
    "$state_dir/configuration.yml"
done < <(jq -r '.pi_appliances.hosts.pi.authelia_oidc_clients[].client_id' "$state_dir/inventory.json")

if rg -q 'client_id: "testapp"' "$state_dir/configuration.yml"; then
  echo "authelia render contract: stale test client was rendered" >&2
  exit 1
fi

printf '%s\n' 'authelia render contract: PASS'
