#!/usr/bin/env bash
set -euo pipefail

if ! command -v ansible-playbook >/dev/null; then
  echo "disabled Pi backup projection: SKIP (ansible-playbook is required in the Pi dev shell)"
  exit 0
fi

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$role_dir/../../../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
export ANSIBLE_LOCAL_TEMP="$test_dir/ansible-local"

cat >"$test_dir/playbook.yml" <<'PLAYBOOK'
---
- name: Verify disabled Pi backups need no compiler target projection
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    pi_backup_enabled: false
  roles:
    - role: restic-backup/ansible
PLAYBOOK

(
  cd "$repo_root/src/infra/pi"
  ansible-playbook --check -i localhost, "$test_dir/playbook.yml" >/dev/null
)

printf '%s\n' 'ok - disabled Pi backup projection does not require target facts'
