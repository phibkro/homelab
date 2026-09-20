#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly repo_root
readonly output="${1:-$repo_root/infra/pi/.devenv/state/generated-inventory.json}"
readonly ansible_user="${PI_ANSIBLE_USER:-nori}"

mkdir -p "$(dirname "$output")"

# The compiler owns every appliance fact. This adapter adds only Ansible's
# transport fields and serializes the secret-free Pi projection.
nix eval --json "$repo_root#lib.noriPiInventory" | jq \
  --arg ansible_user "$ansible_user" \
  '{
    pi_appliances: {
      hosts: {
        pi: (
          .
          + {
            ansible_host: .pi_lan_address,
            ansible_user: $ansible_user
          }
        )
      }
    }
  }' >"$output"

printf '%s\n' "$output"
