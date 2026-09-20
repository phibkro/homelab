#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
readonly script_dir repo_root

fixture="$script_dir/fixtures/inventory.json"
fake_bin="$(mktemp -d)"
output="$(mktemp)"
custom_output="$(mktemp)"
cleanup() {
  rm -rf "$fake_bin" "$output" "$custom_output"
}
trap cleanup EXIT

cp "$script_dir/fixtures/nix" "$fake_bin/nix"
chmod 0755 "$fake_bin/nix"

PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$fixture" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$output" >/dev/null

jq --exit-status --slurpfile expected "$fixture" '
  .pi_appliances.hosts.pi as $pi
  | ($pi | del(.ansible_host, .ansible_user)) == $expected[0]
    and $pi.ansible_host == $expected[0].pi_lan_address
    and $pi.ansible_user == "nori"
' "$output" >/dev/null

PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$fixture" \
  PI_ANSIBLE_USER="deploy-test" \
  "$repo_root/infra/pi/scripts/generate-inventory.sh" "$custom_output" >/dev/null

jq --exit-status '
  .pi_appliances.hosts.pi.ansible_user == "deploy-test"
  and .pi_appliances.hosts.pi.ansible_host == "192.0.2.10"
' "$custom_output" >/dev/null

printf 'inventory generator preserves the compiler projection and adds only Ansible transport fields: PASS\n'
