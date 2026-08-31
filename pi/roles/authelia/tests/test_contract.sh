#!/usr/bin/env bash
set -euo pipefail

role_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tasks_file="$role_root/tasks/main.yml"
config_template="$role_root/templates/configuration.yml.j2"

test -s "$tasks_file"
test -s "$config_template"

# The role must use an immutable image reference and keep the service on the
# host network so Caddy can reach the inventory-selected LAN binding.
rg -q 'ghcr\.io/authelia/authelia:[^[:space:]]+@sha256:[0-9a-f]{64}' "$role_root/defaults/main.yml"
rg -q 'network: host' "$tasks_file"
rg -q 'restart_policy: always' "$tasks_file"

# Secret values are file-backed and never rendered into the configuration
# template or emitted by a debug task.
rg -q 'AUTHELIA_.*_FILE' "$tasks_file"
rg -q 'mode: "0440"' "$tasks_file"
rg -Fq 'user: "{{ authelia_uid }}:{{ authelia_gid }}"' "$tasks_file"
rg -q 'read_only: true' "$tasks_file"
rg -q 'disable_healthcheck: true' "$config_template"
rg -q 'cap_drop:' "$tasks_file"
rg -q 'no-new-privileges:true' "$tasks_file"
rg -q 'authelia_uid: 8000' "$role_root/defaults/main.yml"
rg -q 'authelia_gid: 9000' "$role_root/defaults/main.yml"
if rg -n 'debug:|ansible\.builtin\.debug:' "$tasks_file"; then
  exit 1
fi

# The OIDC client list is rendered through Authelia's template filter so
# PBKDF2 hashes stay outside Git and outside the static YAML.
rg -q 'X_AUTHELIA_CONFIG_FILTERS' "$tasks_file"
rg -q 'secret "/run/secrets/oidc-' "$config_template"
rg -q '^    jwks:' "$config_template"
rg -q 'algorithm: RS256' "$config_template"
rg -q 'mindent 10' "$config_template"
if rg -q 'AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE' "$tasks_file"; then
  echo "deprecated issuer_private_key environment mapping must not be used with JWKS" >&2
  exit 1
fi
rg -q 'subject:' "$config_template"
rg -q 'methods:' "$config_template"
rg -q 'authelia_obsolete_oidc_secret_files' "$tasks_file"
rg -q '== \(authelia_oidc_client_secret_hashes' "$tasks_file"
rg -q 'authelia_oidc_clients \| length > 0' "$tasks_file"
rg -q 'token_endpoint_auth_method' "$config_template"
rg -q "client_secret_post" "$tasks_file"
rg -Fq "map('length')" "$tasks_file"
if rg -q "select\('length'" "$tasks_file"; then
  exit 1
fi

printf '%s\n' 'authelia role contract: ok'
