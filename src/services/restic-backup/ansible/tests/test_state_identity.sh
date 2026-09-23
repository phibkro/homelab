#!/usr/bin/env bash
set -euo pipefail

role_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export ANSIBLE_LOCAL_TEMP="$test_dir/ansible-local"
export BACKUP_TEST_ROLE_DIR="$role_dir"

# Load the real role defaults and let Ansible evaluate their templates. The
# fixture intentionally neither copies the hash algorithm nor invokes the role.
cat >"$test_dir/playbook.yml" <<'PLAYBOOK'
---
- name: Backup completion markers follow the public destination identity
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Load the production backup defaults
      ansible.builtin.include_vars:
        file: "{{ lookup('env', 'BACKUP_TEST_ROLE_DIR') }}/defaults/main.yml"

    - name: Declare a public test destination
      ansible.builtin.set_fact:
        baseline_destination:
          host: receiver.example.invalid
          address: 192.0.2.10
          user: restic
          prefix: ""
          known_host: receiver.example.invalid ssh-ed25519 TESTPUBLICKEY

    - name: Select the initial destination
      ansible.builtin.set_fact:
        pi_backup_enabled: true
        pi_backup_target_host: "{{ baseline_destination.host }}"
        pi_backup_target_address: "{{ baseline_destination.address }}"
        pi_backup_target_user: "{{ baseline_destination.user }}"
        pi_backup_repository_prefix: "{{ baseline_destination.prefix }}"
        pi_backup_target_known_host: "{{ baseline_destination.known_host }}"

    - name: Capture the evaluated initial marker directory
      ansible.builtin.set_fact:
        baseline_state: "{{ pi_backup_state_dir }}"

    - name: Reject reuse of legacy unscoped success markers
      ansible.builtin.assert:
        that:
          - baseline_state is match('^/var/lib/pi-restic/[^/]+$')
          - baseline_state ~ '/pihole/last-success' != '/var/lib/pi-restic/pihole/last-success'

    - name: Check each independently changed destination field
      ansible.builtin.include_tasks: destination.yml
      loop:
        - { name: identical, change: {}, changed: false }
        - { name: hostname, change: { host: other.example.invalid }, changed: true }
        - { name: address, change: { address: 192.0.2.11 }, changed: true }
        - { name: user, change: { user: other-restic }, changed: true }
        - { name: key, change: { known_host: 'receiver.example.invalid ssh-ed25519 OTHERPUBLICKEY' }, changed: true }
        - { name: repository, change: { prefix: /other }, changed: true }
        - { name: original-again, change: {}, changed: false }
      loop_control:
        loop_var: destination_case
        label: "{{ destination_case.name }}"
PLAYBOOK

cat >"$test_dir/destination.yml" <<'DESTINATION'
---
- name: Select this destination without retaining previous case overrides
  ansible.builtin.set_fact:
    pi_backup_target_host: "{{ destination_case.change.host | default(baseline_destination.host) }}"
    pi_backup_target_address: "{{ destination_case.change.address | default(baseline_destination.address) }}"
    pi_backup_target_user: "{{ destination_case.change.user | default(baseline_destination.user) }}"
    pi_backup_repository_prefix: "{{ destination_case.change.prefix | default(baseline_destination.prefix) }}"
    pi_backup_target_known_host: "{{ destination_case.change.known_host | default(baseline_destination.known_host) }}"

- name: Assert that only the same destination can reuse completion markers
  ansible.builtin.assert:
    that:
      - (pi_backup_state_dir != baseline_state) == destination_case.changed
      - ((pi_backup_state_dir ~ '/pihole/last-success') != (baseline_state ~ '/pihole/last-success')) == destination_case.changed
    fail_msg: "Incorrect completion marker identity for {{ destination_case.name }}"
DESTINATION

ansible-playbook -i localhost, "$test_dir/playbook.yml"
echo 'ok - Pi backup destination marker identity'
