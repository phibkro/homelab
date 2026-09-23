#!/usr/bin/env bash
set -euo pipefail

readonly action="${1:-}"
if [[ "$action" != "plan" && "$action" != "deploy" && "$action" != "enroll" && "$action" != "inspect-caddy" ]]; then
  echo "usage: $0 plan|deploy|enroll|inspect-caddy" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
readonly repo_root
readonly known_hosts="${PI_SSH_KNOWN_HOSTS:-}"

if [[ "$action" == "enroll" && ( -z "${TAILSCALE_AUTH_KEY:-}" || ${#TAILSCALE_AUTH_KEY} -lt 20 ) ]]; then
  echo "TAILSCALE_AUTH_KEY must be set to at least 20 characters for enrollment" >&2
  exit 1
fi

if [[ ( "$action" == "plan" || "$action" == "deploy" ) && ( -z "${PIHOLE_WEB_PASSWORD:-}" || ${#PIHOLE_WEB_PASSWORD} -lt 12 ) ]]; then
  echo "PIHOLE_WEB_PASSWORD must be set to at least 12 characters" >&2
  exit 1
fi
if [[ -z "$known_hosts" || ! -f "$known_hosts" ]]; then
  echo "PI_SSH_KNOWN_HOSTS must name an existing pinned known-hosts file" >&2
  exit 1
fi

inventory="$(bash "$repo_root/src/infra/pi/scripts/generate-inventory.sh")"
readonly inventory

if [[ "$action" == "plan" || "$action" == "deploy" ]]; then
  missing_oidc_secrets=()
  while IFS= read -r secret_name; do
    if [[ -z "${!secret_name:-}" ]]; then
      missing_oidc_secrets+=("$secret_name")
    fi
  done < <(
    jq --exit-status --raw-output \
      '.pi_appliances.hosts.pi.authelia_oidc_clients[].secret_hash_env_name' \
      "$inventory"
  )
  if (( ${#missing_oidc_secrets[@]} > 0 )); then
    printf 'Missing SecretSpec values for active OIDC clients: %s\n' \
      "${missing_oidc_secrets[*]}" >&2
    exit 1
  fi
fi
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

if [[ "$action" == "inspect-caddy" ]]; then
  ansible_user="$(jq --exit-status --raw-output \
    '._meta.hostvars.pi.ansible_user | select(type == "string" and length > 0)' \
    <<<"$resolved_inventory")"
  readonly ansible_user
  exec ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$known_hosts_absolute" \
    "$ansible_user@$target" \
    sudo --non-interactive podman exec caddy cat /etc/caddy/Caddyfile
fi

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

playbook="$repo_root/src/infra/pi/playbooks/pi.yml"
if [[ "$action" == "enroll" ]]; then
  playbook="$repo_root/src/infra/pi/playbooks/enroll-tailscale.yml"
fi
readonly playbook

args=(
  --inventory "$inventory"
  --extra-vars "$extra_vars"
  --diff
  "$playbook"
)
if [[ "$action" == "plan" ]]; then
  args=(--check "${args[@]}")
fi

exec ansible-playbook "${args[@]}"
