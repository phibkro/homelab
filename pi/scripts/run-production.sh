#!/usr/bin/env bash
set -euo pipefail

readonly action="${1:-}"
if [[ "$action" != "plan" && "$action" != "deploy" ]]; then
  echo "usage: $0 plan|deploy" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly repo_root
readonly known_hosts="${PI_SSH_KNOWN_HOSTS:-}"

if [[ -z "${PIHOLE_WEB_PASSWORD:-}" || ${#PIHOLE_WEB_PASSWORD} -lt 12 ]]; then
  echo "PIHOLE_WEB_PASSWORD must be set to at least 12 characters" >&2
  exit 1
fi
if [[ -z "$known_hosts" || ! -f "$known_hosts" ]]; then
  echo "PI_SSH_KNOWN_HOSTS must name an existing pinned known-hosts file" >&2
  exit 1
fi

inventory="$(bash "$repo_root/pi/scripts/generate-inventory.sh")"
readonly inventory
target="$(jq --raw-output '._meta.hostvars.pi.ansible_host' "$inventory")"
readonly target

if ! ssh-keygen -F "$target" -f "$known_hosts" >/dev/null; then
  echo "No pinned SSH key for $target in $known_hosts" >&2
  exit 1
fi

if [[ "$action" == "deploy" ]]; then
  readonly expected_confirmation="pi@$target"
  if [[ "${PI_DEPLOY_CONFIRM:-}" != "$expected_confirmation" ]]; then
    echo "Refusing deployment: set PI_DEPLOY_CONFIRM=$expected_confirmation" >&2
    exit 1
  fi
fi

known_hosts_dir="$(cd "$(dirname "$known_hosts")" && pwd)"
readonly known_hosts_dir
known_hosts_absolute="$known_hosts_dir/$(basename "$known_hosts")"
readonly known_hosts_absolute

args=(
  --inventory "$inventory"
  --extra-vars "ansible_ssh_common_args=-o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts_absolute"
  --diff
  "$repo_root/pi/playbooks/pi.yml"
)
if [[ "$action" == "plan" ]]; then
  args=(--check "${args[@]}")
fi

exec ansible-playbook "${args[@]}"
