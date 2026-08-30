#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
fail() { echo "vector role contract: $*" >&2; exit 1; }

[[ -f "$role_dir/defaults/main.yml" ]] || fail "defaults are missing"
[[ -f "$role_dir/templates/vector.yaml.j2" ]] || fail "Vector config template is missing"
[[ -f "$role_dir/templates/vector.service.j2" ]] || fail "systemd unit is missing"
rg -q 'vector_base_image.*sha256:' "$role_dir/tasks/main.yml" || fail "immutable base image assertion is missing"
[[ -f "$role_dir/templates/Containerfile.j2" ]] || fail "journald image build is missing"
rg -q 'libsystemd0' "$role_dir/templates/Containerfile.j2" || fail "libsystemd runtime is missing"
rg -q 'systemd' "$role_dir/templates/Containerfile.j2" || fail "journalctl provider is missing"
rg -q 'vector_victorialogs_endpoint.*insert/elasticsearch' "$role_dir/tasks/main.yml" || fail "explicit Elasticsearch endpoint assertion is missing"
rg -q 'type: journald' "$role_dir/templates/vector.yaml.j2" || fail "journald source is missing"
! rg -q 'journal_directory' "$role_dir/templates/vector.yaml.j2" || fail "journal discovery must use host defaults"
rg -q 'type: elasticsearch' "$role_dir/templates/vector.yaml.j2" || fail "Elasticsearch bulk sink is missing"
rg -q 'mode: bulk' "$role_dir/templates/vector.yaml.j2" || fail "bulk mode is missing"
rg -q '_stream_fields: host,unit' "$role_dir/templates/vector.yaml.j2" || fail "stream identity mapping is missing"
rg -q 'vector_data_dir' "$role_dir/tasks/main.yml" || fail "persistent cursor state is missing"
rg -q '/run/log/journal:/run/log/journal:ro' "$role_dir/tasks/main.yml" || fail "runtime journal mount is missing"
rg -q '/etc/machine-id:/etc/machine-id:ro' "$role_dir/tasks/main.yml" || fail "machine identity mount is missing"
rg -q 'getent' "$role_dir/tasks/main.yml" || fail "journal group must be resolved by name"
rg -q 'Validate Vector executable and journald runtime' "$role_dir/tasks/main.yml" || fail "journald runtime validation is missing"
rg -q 'validate' "$role_dir/tasks/main.yml" || fail "Vector config validation is missing"
rg -q 'current_boot_only: true' "$role_dir/templates/vector.yaml.j2" \
  || fail "Vector journald input must use the systemd 257-compatible cursor mode"
rg -q '/var/lib/vector:rw,noexec,nosuid,size=16m,uid=\{\{ vector_container_user.*gid=\{\{ vector_container_user' "$role_dir/tasks/main.yml" \
  || fail "Vector validation does not use ephemeral writable state"
if rg -Uq '      - validate\n      - --config' "$role_dir/tasks/main.yml"; then
  fail "Vector 0.58 validate expects configuration paths positionally"
fi
rg -q 'recreate:.*vector_containerfile.changed' "$role_dir/tasks/main.yml" || fail "custom image changes must recreate the container"
rg -q 'no-new-privileges' "$role_dir/tasks/main.yml" || fail "hardening is missing"
rg -q 'cap_drop:' "$role_dir/tasks/main.yml" || fail "capability drop is missing"
rg -q 'read_only: true' "$role_dir/tasks/main.yml" || fail "read-only rootfs is missing"
rg -q 'Restart=always' "$role_dir/templates/vector.service.j2" || fail "restart policy is missing"
rg -q 'podman start --attach vector' "$role_dir/templates/vector.service.j2" || fail "boot restore is missing"
echo "vector role contract: PASS"
