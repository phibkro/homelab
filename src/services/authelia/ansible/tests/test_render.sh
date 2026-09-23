#!/usr/bin/env bash
set -euo pipefail

for command in ansible-playbook jq rg; do
  if ! command -v "$command" >/dev/null; then
    echo "authelia render contract: SKIP ($command is required in the Pi dev shell)"
    exit 0
  fi
done

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$role_dir/../../../.." && pwd)"
state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

"$repo_root/src/infra/pi/scripts/generate-inventory.sh" "$state_dir/inventory.json" >/dev/null
jq '.pi_appliances.hosts.pi' "$state_dir/inventory.json" >"$state_dir/inventory-vars.json"

cat >"$state_dir/playbook.yml" <<EOF
---
- name: Render Authelia configuration from the compiler projection
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - "$role_dir/defaults/main.yml"
    - "$repo_root/src/infra/pi/playbooks/group_vars/all.yml"
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
expected_authelia_url="$(jq --exit-status --raw-output '
  .pi_appliances.hosts.pi.pi_routes
  | map(select(.name == "auth"))
  | if length == 1 then "https://" + .[0].hostname
    else error("expected exactly one compiled auth route")
    end
' "$state_dir/inventory.json")"
rg -Fq "authelia_url: \"$expected_authelia_url\"" "$state_dir/configuration.yml"


while IFS= read -r client_id; do
  rg -Fq "      - client_id: \"$client_id\"" "$state_dir/configuration.yml"
  rg -Fq "client_secret: {{ secret \"/run/secrets/oidc-$client_id-client-secret-hash\" }}" \
    "$state_dir/configuration.yml"
done < <(jq -r '.pi_appliances.hosts.pi.authelia_oidc_clients[].client_id' "$state_dir/inventory.json")

ansible-playbook -i localhost, "$state_dir/playbook.yml" \
  --extra-vars '{"authelia_oidc_clients":[]}' >/dev/null
rg -Uq $'    clients:\n      \[\]' "$state_dir/configuration.yml"
if rg -q '^      - client_id:' "$state_dir/configuration.yml"; then
  echo "authelia render contract: empty client projection rendered a client" >&2
  exit 1
fi

cat >"$state_dir/contract-vars.yml" <<'EOF'
authelia_enabled: true
pi_service_bind_address: 192.168.1.225
authelia_port: 9091
authelia_jwt_secret: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
authelia_session_secret: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
authelia_storage_encryption_key: cccccccccccccccccccccccccccccccccccccccc
authelia_oidc_hmac_secret: dddddddddddddddddddddddddddddddddddddddd
authelia_oidc_issuer_private_key: "-----BEGIN PRIVATE KEY----- test"
authelia_users_database: "users: {}"
authelia_oidc_clients: []
authelia_oidc_client_secret_hashes: {}
EOF
cat >"$state_dir/contract-playbook.yml" <<EOF
---
- name: Validate forward-auth-only Authelia inputs
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - "$role_dir/defaults/main.yml"
    - "$state_dir/contract-vars.yml"
  tasks:
    - name: Load the actual Authelia role tasks
      ansible.builtin.import_tasks: "$role_dir/tasks/main.yml"
EOF
ansible-playbook -i localhost, "$state_dir/contract-playbook.yml" \
  --tags authelia-contract >/dev/null

if rg -q 'client_id: "testapp"' "$state_dir/configuration.yml"; then
  echo "authelia render contract: stale test client was rendered" >&2
  exit 1
fi

printf '%s\n' 'authelia render contract: PASS'
