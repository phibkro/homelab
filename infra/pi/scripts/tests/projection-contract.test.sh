#!/usr/bin/env bash
set -euo pipefail

for command in ansible-playbook jq; do
  if ! command -v "$command" >/dev/null; then
    echo "Pi projection contract: SKIP ($command is required in the Pi dev shell)"
    exit 0
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
secret_spec="$repo_root/infra/pi/secretspec.toml"
state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
export ANSIBLE_LOCAL_TEMP="$state_dir/ansible-local"

inventory="$state_dir/inventory.json"
inventory_vars="$state_dir/inventory-vars.json"
expected_vars="$state_dir/expected-vars.json"
"$repo_root/infra/pi/scripts/generate-inventory.sh" "$inventory" >/dev/null
jq '.pi_appliances.hosts.pi' "$inventory" >"$inventory_vars"

jq --exit-status '
  .pi_appliances.hosts.pi as $pi
  | ($pi.pi_routes | map(select(.name == "auth"))) as $auth_routes
  | ($pi.pi_routes | map(select(.name == "alert"))) as $alert_routes
  | ($pi.pi_routes | map(select(.name == "metrics"))) as $metrics_routes
  | if ($auth_routes | length) == 1
       and ($alert_routes | length) == 1
       and ($metrics_routes | length) == 1
    then
      ($metrics_routes[0]) as $metrics_route
      | ($pi.authelia_oidc_clients
         | map(select(.client_id == $metrics_route.name))) as $metrics_clients
      | if ($metrics_clients | length) == 1 then
          {
            expected_authelia_url: "https://" + $auth_routes[0].hostname,
            expected_ntfy_base_url: "https://" + $alert_routes[0].hostname,
            expected_caddy_forward_auth_redirect_url: "https://" + $auth_routes[0].hostname,
            expected_beszel_oidc_client_id: $metrics_clients[0].client_id,
            expected_beszel_oidc_issuer_url: "https://" + $auth_routes[0].hostname
          }
        else error("expected exactly one compiled Beszel OIDC client")
        end
    else error("expected exactly one compiled auth, alert, and metrics route")
    end
' "$inventory" >"$expected_vars"

cat >"$state_dir/playbook.yml" <<EOF
---
- name: Validate Pi projection consumers
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - "$repo_root/infra/pi/playbooks/group_vars/all.yml"
    - "$inventory_vars"
    - "$expected_vars"
  tasks:
    - name: Resolve service integration values from the compiler projection
      ansible.builtin.assert:
        that:
          - authelia_url == expected_authelia_url
          - ntfy_base_url == expected_ntfy_base_url
          - caddy_forward_auth_redirect_url == expected_caddy_forward_auth_redirect_url
          - beszel_oidc_client_id == expected_beszel_oidc_client_id
          - beszel_oidc_issuer_url == expected_beszel_oidc_issuer_url
EOF

ansible-playbook -i localhost, "$state_dir/playbook.yml" >/dev/null

compiled_names="$state_dir/compiled-oidc-secret-names"
profile_names="$state_dir/profile-oidc-secret-names"
deployment_names="$state_dir/deployment-oidc-secret-names"
jq --exit-status --raw-output \
  '.pi_appliances.hosts.pi.authelia_oidc_clients[].secret_hash_env_name' \
  "$inventory" | LC_ALL=C sort >"$compiled_names"

extract_profile_declarations() {
  local section="" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "[profiles.production]") section=production ;;
      "["*"]") section="" ;;
    esac
    if [[ "$section" == production
      && "$line" =~ ^[[:space:]]*(OIDC_[A-Z0-9_]+_CLIENT_SECRET_HASH)[[:space:]]*= ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done <"$secret_spec"
}

extract_deployment_scope() {
  local section="" in_secrets=false line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "[scopes.deployment]") section=deployment; in_secrets=false ;;
      "["*"]") section=""; in_secrets=false ;;
    esac
    [[ "$section" == deployment ]] || continue
    if [[ "$line" == "secrets = [" ]]; then
      in_secrets=true
      continue
    fi
    if [[ "$in_secrets" == true && "$line" == "]" ]]; then
      in_secrets=false
      continue
    fi
    if [[ "$in_secrets" == true
      && "$line" =~ \"(OIDC_[A-Z0-9_]+_CLIENT_SECRET_HASH)\" ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done <"$secret_spec"
}

extract_profile_declarations | LC_ALL=C sort >"$profile_names"
extract_deployment_scope | LC_ALL=C sort >"$deployment_names"

for names in "$compiled_names" "$profile_names" "$deployment_names"; do
  if [[ ! -s "$names" ]]; then
    echo "Pi OIDC SecretSpec contract has an empty set: $names" >&2
    exit 1
  fi
  if LC_ALL=C uniq -d "$names" | grep -q .; then
    echo "Pi OIDC SecretSpec contract has duplicate names: $names" >&2
    exit 1
  fi
done

if ! cmp -s "$profile_names" "$deployment_names"; then
  echo 'SecretSpec OIDC declarations differ from its deployment scope' >&2
  diff -u "$profile_names" "$deployment_names" >&2 || true
  exit 1
fi
if ! comm -23 "$compiled_names" "$profile_names" | cmp -s - /dev/null; then
  echo 'Compiled OIDC secret names are missing from SecretSpec' >&2
  comm -23 "$compiled_names" "$profile_names" >&2
  exit 1
fi

printf '%s\n' 'Pi projection contract: PASS'
