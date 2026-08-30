#!/usr/bin/env bash
set -euo pipefail

role_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { echo "backup role contract: $*" >&2; exit 1; }

for file in defaults/main.yml tasks/main.yml handlers/main.yml \
  templates/backup.sh.j2 templates/maintenance.sh.j2 \
  templates/backup.service.j2 templates/maintenance.service.j2 \
  templates/timer.j2 templates/freshness.sh.j2 templates/freshness.service.j2 \
  templates/freshness.timer.j2 templates/restore-disposable.sh.j2; do
  [[ -f "$role_dir/$file" ]] || fail "missing $file"
done

rg -q 'pi_backup_jobs: \[\]' "$role_dir/defaults/main.yml" || fail "manifest must be explicit"
rg -q 'pi_backup_approved_source_prefixes:' "$role_dir/vars/main.yml" || fail "immutable source allowlist is missing"
rg -q 'item in pi_backup_effective_source_prefixes' "$role_dir/tasks/main.yml" \
  || fail "manifest paths are not checked against the exact allowlist"
rg -q '/var/lib/containers/storage/volumes/pihole-data/_data' "$role_dir/vars/main.yml" || fail "Pi-hole volume path is not narrowly approved"
rg -q '/opt/caddy/data' "$role_dir/vars/main.yml" || fail "Caddy data path is not approved"
rg -q '/etc/authelia/configuration.yml' "$role_dir/vars/main.yml" || fail "Authelia config path is not approved"
rg -q 'pi_backup_aurora_host: aurora\.saola-matrix\.ts\.net' "$role_dir/defaults/main.yml" || fail "Aurora host contract missing"
rg -q 'HostName=\{\{ pi_backup_aurora_address \}\}' "$role_dir/templates/backup.sh.j2" || fail "Aurora tailnet address override missing"
rg -q 'HostKeyAlias=\{\{ pi_backup_aurora_host \}\}' "$role_dir/templates/backup.sh.j2" || fail "Aurora host-key alias missing"
rg -q 'pi_backup_repository_prefix: "/pi"' "$role_dir/defaults/main.yml" || fail "Aurora repository prefix missing"
rg -q 'StrictHostKeyChecking=yes' "$role_dir/templates/backup.sh.j2" || fail "strict host verification missing"
rg -q 'UserKnownHostsFile=' "$role_dir/templates/backup.sh.j2" || fail "pinned known_hosts missing"
rg -q 'IdentitiesOnly=yes' "$role_dir/templates/maintenance.sh.j2" || fail "SSH identity pin missing"
rg -q 'mode: "0400"' "$role_dir/tasks/main.yml" || fail "root-only secret mode missing"
rg -q 'pi_backup_restic_password' "$role_dir/tasks/main.yml" || fail "restic password input missing"
rg -q 'pi_backup_ssh_private_key' "$role_dir/tasks/main.yml" || fail "SSH key input missing"
rg -q 'content: "\{\{ pi_backup_ssh_private_key | trim \}\}\\n"' "$role_dir/tasks/main.yml" \
  || fail "SSH key file must end with exactly one newline"
! rg -q 'pi_backup_restic_password|pi_backup_ssh_private_key' "$role_dir/templates" || fail "secret content is rendered into runtime templates"
rg -q 'no_log: true' "$role_dir/tasks/main.yml" || fail "secret installation is not hidden from task output"
rg -q 'keep-daily' "$role_dir/templates/maintenance.sh.j2" || fail "retention missing"
rg -q 'forget --prune' "$role_dir/templates/maintenance.sh.j2" || fail "prune missing"
rg -q 'restic.*check' "$role_dir/templates/maintenance.sh.j2" || fail "check missing"
rg -q -- '--read-data-subset=10%' "$role_dir/templates/maintenance.sh.j2" || fail "10 percent check missing"
rg -q 'cat config' "$role_dir/templates/backup.sh.j2" || fail "idempotent repository initialization check missing"
rg -q 'restic.*init' "$role_dir/templates/backup.sh.j2" || fail "repository initialization missing"
rg -q 'last-success' "$role_dir/templates/backup.sh.j2" || fail "freshness marker missing"
rg -q 'Create missing initial Pi backup snapshots sequentially' "$role_dir/tasks/main.yml" \
  || fail "initial snapshots are not created before freshness monitoring"
rg -q 'pi_backup_initial_markers.results' "$role_dir/tasks/main.yml" \
  || fail "initial backup creation is not marker-gated"
rg -q 'snapshots --latest 1 --json' "$role_dir/templates/freshness.sh.j2" || fail "remote freshness query missing"
rg -q 'pi_backup_effective_jobs' "$role_dir/templates/freshness.sh.j2" || fail "freshness does not cover effective manifest"
rg -q 'stale owned Pi backup artifacts' "$role_dir/tasks/main.yml" || fail "stale artifact cleanup missing"
rg -q 'pi_backup_expected_runtime_files' "$role_dir/tasks/main.yml" || fail "artifact ownership allowlist missing"
rg -q 'homelab-pi-backup-role: managed' "$role_dir/templates" || fail "artifact ownership marker missing"
rg -q 'contains: "homelab-pi-backup-role: managed"' "$role_dir/tasks/main.yml" || fail "stale cleanup is not marker-scoped"
rg -q 'check-weekly' "$role_dir/tasks/main.yml" || fail "weekly metadata check unit missing"
rg -q 'check-monthly' "$role_dir/tasks/main.yml" || fail "monthly data check unit missing"
rg -q 'pi_backup_metadata_check_schedule: "Sun \*-\*-\* 05:30:00"' "$role_dir/defaults/main.yml" || fail "weekly check schedule drifted"
rg -q 'pi_backup_data_check_schedule: "\*-\*-01 06:00:00"' "$role_dir/defaults/main.yml" || fail "monthly check schedule is not staggered"
rg -q '^OnCalendar=\{\{ timer_schedule \}\}$' "$role_dir/templates/timer.j2" \
  || fail "systemd calendar expression must not contain literal shell quotes"
rg -q "schedule.*is not search" "$role_dir/tasks/main.yml" \
  || fail "calendar expressions must reject unit-file line injection"
rg -q 'pi_backup_tailscale_identity_enabled: false' "$role_dir/defaults/main.yml" || fail "Tailscale backup is not opt-in"
rg -q 'pi_backup_tailscale_identity_paths' "$role_dir/tasks/main.yml" || fail "Tailscale explicit path assertion missing"
rg -q 'pi_backup_restore_dir' "$role_dir/templates/restore-disposable.sh.j2" || fail "disposable restore root missing"
rg -q 'mktemp -d' "$role_dir/templates/restore-disposable.sh.j2" || fail "restore must use atomic staging"
rg -q 'mv -T --.*destination' "$role_dir/templates/restore-disposable.sh.j2" || fail "restore must publish atomically"
rg -q '\-e "\$destination".*\-L "\$destination"' "$role_dir/templates/restore-disposable.sh.j2" || fail "restore must reject existing destinations"
for service in backup.service.j2 maintenance.service.j2 freshness.service.j2; do
  rg -q '^User=root$' "$role_dir/templates/$service" || fail "$service is not root-owned"
  rg -q '^ProtectSystem=strict$' "$role_dir/templates/$service" || fail "$service lacks filesystem protection"
done
! rg -q '/var/lib/containers|/var/lib/[^ ]*containers' "$role_dir/defaults" "$role_dir/templates" || fail "broad container storage path found"
! rg -q 'state: absent.*pi_backup_repository|pi_backup_repository.*state: absent' "$role_dir/tasks" "$role_dir/templates" || fail "repository cleanup is destructive"
echo 'ok - Pi backup role contract'
