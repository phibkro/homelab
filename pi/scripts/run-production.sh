#!/usr/bin/env bash
set -euo pipefail

readonly action="${1:-}"
if [[ "$action" != "plan" && "$action" != "deploy" && "$action" != "enroll" ]]; then
  echo "usage: $0 plan|deploy|enroll" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly repo_root
readonly known_hosts="${PI_SSH_KNOWN_HOSTS:-}"

if [[ "$action" == "enroll" && ( -z "${TAILSCALE_AUTH_KEY:-}" || ${#TAILSCALE_AUTH_KEY} -lt 20 ) ]]; then
  echo "TAILSCALE_AUTH_KEY must be set to at least 20 characters for enrollment" >&2
  exit 1
fi

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
target="$(jq --raw-output '.pi_appliances.hosts.pi.ansible_host' "$inventory")"
readonly target

resolved_inventory="$(ansible-inventory --inventory "$inventory" --list)"
readonly resolved_inventory
if ! jq --exit-status \
  --arg target "$target" \
  '.pi_appliances.hosts == ["pi"]
   and ._meta.hostvars.pi.ansible_host == $target' \
  <<<"$resolved_inventory" >/dev/null; then
  echo "Generated inventory did not resolve exactly one expected Pi target" >&2
  exit 1
fi

if ! ssh-keygen -F "$target" -f "$known_hosts" >/dev/null; then
  echo "No pinned SSH key for $target in $known_hosts" >&2
  exit 1
fi

if [[ "$action" == "deploy" || "$action" == "enroll" ]]; then
  readonly expected_confirmation="pi@$target"
  if [[ "${PI_DEPLOY_CONFIRM:-}" != "$expected_confirmation" ]]; then
    echo "Refusing $action: set PI_DEPLOY_CONFIRM=$expected_confirmation" >&2
    exit 1
  fi
fi

known_hosts_dir="$(cd "$(dirname "$known_hosts")" && pwd)"
readonly known_hosts_dir
known_hosts_absolute="$known_hosts_dir/$(basename "$known_hosts")"
readonly known_hosts_absolute
tailscale_enroll=false
if [[ "$action" == "enroll" ]]; then
  tailscale_enroll=true
fi
readonly tailscale_enroll

extra_vars="$(jq --null-input --compact-output \
  --arg common_args \
    "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts_absolute" \
  --argjson tailscale_enroll "$tailscale_enroll" \
  '{ansible_ssh_common_args: $common_args, tailscale_enroll: $tailscale_enroll}')"
readonly extra_vars

args=(
  --inventory "$inventory"
  --extra-vars "$extra_vars"
  --diff
  "$repo_root/pi/playbooks/pi.yml"
)
if [[ "$action" == "plan" ]]; then
  args=(--check "${args[@]}")
fi

exec ansible-playbook "${args[@]}"
