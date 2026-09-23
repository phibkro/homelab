#!/usr/bin/env bash
set -euo pipefail
trap 'printf "Pi VM test failed at line %s\n" "$LINENO" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
readonly repo_root
cd "$repo_root"

readonly cache_dir="${TMPDIR:-/tmp}/homelab-pi-cache"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=vm-lifecycle.sh
source "$repo_root/src/infra/pi/scripts/vm-lifecycle.sh"
vm_lifecycle_init "$repo_root"
readonly state_dir attempt_dir
readonly image_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2"
readonly base_image="$cache_dir/debian-12-genericcloud-arm64.qcow2"
readonly overlay="$state_dir/root.qcow2"
readonly seed="$state_dir/seed.img"
readonly ssh_key="$state_dir/id_ed25519"
readonly authelia_issuer_key="$state_dir/authelia-issuer-rsa"
readonly qemu_log="$attempt_dir/qemu.log"
readonly ansible_log="$attempt_dir/ansible.log"
readonly reuse_vm="${PI_VM_REUSE:-false}"
readonly ignore_host_load="${PI_VM_IGNORE_HOST_LOAD:-false}"

mkdir -p "$cache_dir"
vm_phase preflight

if [[ "$ignore_host_load" != true ]]; then
  available_kib="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
  if [[ -z "$available_kib" || "$available_kib" -lt 8388608 ]]; then
    echo "Refusing ARM emulation with less than 8 GiB memory available" >&2
    exit 1
  fi
  if systemctl list-units --state=activating,running --plain --no-legend \
    'restic-backups-*.service' | grep -q .; then
    echo "Refusing ARM emulation while a restic backup is active" >&2
    exit 1
  fi
  if pgrep -f 'nix flake check' >/dev/null; then
    echo "Refusing ARM emulation while nix flake check is active" >&2
    exit 1
  fi
fi

if [[ ! -s "$base_image" ]]; then
  vm_phase download-base-image
  download="$(mktemp "$cache_dir/download.XXXXXXXX")"
  curl --fail --location --output "$download" "$image_url"
  mv "$download" "$base_image"
fi

if [[ "$reuse_vm" == true ]]; then
  for artifact in "$overlay" "$seed" "$ssh_key" "$authelia_issuer_key"; do
    if [[ ! -f "$artifact" || ! -s "$artifact" || -L "$artifact" ]]; then
      echo "Cannot reuse the ARM64 guest; missing artifact: $artifact" >&2
      exit 1
    fi
  done
else
  vm_phase create-guest
  ssh-keygen -q -t ed25519 -N '' -f "$ssh_key"
  ssh-keygen -q -t rsa -b 2048 -m PEM -N '' -f "$authelia_issuer_key"
  qemu-img create -q -f qcow2 -F qcow2 -b "$base_image" "$overlay" 16G

  sed "s|__SSH_PUBLIC_KEY__|$(<"$ssh_key.pub")|" \
    src/infra/pi/tests/vm/user-data.yml > "$state_dir/user-data.yml"
  cloud-localds \
    --network-config=src/infra/pi/tests/vm/network-config.yml \
    "$seed" \
    "$state_dir/user-data.yml" \
    src/infra/pi/tests/vm/meta-data.yml
fi

qemu_prefix="$(dirname "$(dirname "$(readlink -f "$(command -v qemu-system-aarch64)")")")"
readonly qemu_prefix
readonly firmware="$qemu_prefix/share/qemu/edk2-aarch64-code.fd"
if [[ ! -f "$firmware" ]]; then
  echo "ARM64 UEFI firmware not found at $firmware" >&2
  exit 1
fi

vm_phase boot-guest
qemu_args=(
  -machine "virt,accel=tcg"
  -cpu cortex-a72
  -smp 4
  -m 3072
  -nographic
  -bios "$firmware"
  -drive "if=virtio,format=qcow2,file=$overlay"
  -drive "if=virtio,format=raw,readonly=on,file=$seed"
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8053-:53,hostfwd=udp:127.0.0.1:8053-:53,hostfwd=tcp:127.0.0.1:8081-:8081,hostfwd=tcp:127.0.0.1:8080-:80,hostfwd=tcp:127.0.0.1:9443-:443"
  -device "virtio-net-pci,netdev=net0"
)
vm_record_command qemu-system-aarch64 "${qemu_args[@]}"
qemu-system-aarch64 "${qemu_args[@]}" \
  >"$qemu_log" 2>&1 &
qemu_pid=$!
vm_guard_process

export PI_VM_SSH_KEY="$ssh_key"
export ANSIBLE_LOG_PATH="$ansible_log"
readonly test_inventory="$repo_root/src/infra/pi/inventory/test.yml"
readonly test_projection="$state_dir/test-inventory.json"
ansible-inventory --inventory "$test_inventory" --list >"$test_projection"
test_inventory_hostname="$(
  jq --exit-status --raw-output \
    '.pi_appliances.hosts
     | if type == "array" and length == 1 then .[0]
       else error("test inventory must contain exactly one Pi host")
       end' \
    "$test_projection"
)"
readonly test_inventory_hostname
test_pi_domain="$(
  jq --exit-status --raw-output --arg host "$test_inventory_hostname" \
    '._meta.hostvars[$host].pi_domain
     | if type == "string" and length > 0 then .
       else error("test inventory must project pi_domain")
       end' \
    "$test_projection"
)"
pihole_hostname="$(
  jq --exit-status --raw-output --arg host "$test_inventory_hostname" \
    '._meta.hostvars[$host].pi_routes
     | map(select(.name == "pihole"))
     | if length == 1 and (.[0].hostname | type == "string")
       then .[0].hostname
       else error("test inventory must project exactly one Pi-hole route")
       end' \
    "$test_projection"
)"
readonly test_pi_domain pihole_hostname
readonly unknown_hostname="unknown.${test_pi_domain}"

export PIHOLE_WEB_PASSWORD="emulation-only-password"
export AUTHELIA_JWT_SECRET="emulation-authelia-jwt-secret-000000000000000000"
export AUTHELIA_SESSION_SECRET="emulation-authelia-session-secret-00000000000000"
export AUTHELIA_STORAGE_ENCRYPTION_KEY="emulation-authelia-storage-key-000000000000"
export AUTHELIA_OIDC_HMAC_SECRET="emulation-authelia-oidc-hmac-00000000000000"
authelia_issuer_private_key="$(<"$authelia_issuer_key")"
export AUTHELIA_OIDC_ISSUER_PRIVATE_KEY="$authelia_issuer_private_key"
# The literal password hash must not expand shell variables.
# shellcheck disable=SC2016
export AUTHELIA_USERS_DATABASE='users:
  emulation:
    displayname: Emulation User
    password: $argon2id$v=19$m=65536,t=3,p=4$5pFr3Ws3jZ1H/J3Q1i09xQ$jnw3Da27IOwGu/087Ham4ffamjF4Zo4x6orle9uMs7E
    email: emulation@example.invalid
    groups:
      - operators'
export OIDC_METRICS_CLIENT_SECRET_HASH="\$pbkdf2-sha512\$310000\$CRgk02fRAmrJO85h.OVnzQ\$1dHFWLvmTbpwzshm0x5c1.sxuuWJ2R8yykw7XF1lsuE.ThMlv27hfIs2njPv2cNqmz1nxp9xEa4HcTAmvWDJPg"
export OIDC_PHOTOS_CLIENT_SECRET_HASH="$OIDC_METRICS_CLIENT_SECRET_HASH"
export OIDC_NEWS_CLIENT_SECRET_HASH="$OIDC_METRICS_CLIENT_SECRET_HASH"
export OIDC_VAULT_CLIENT_SECRET_HASH="$OIDC_METRICS_CLIENT_SECRET_HASH"
export NTFY_PUBLISHER_TOKEN="tk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export NTFY_PUBLISHER_PASSWORD_HASH="\$2b\$12\$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export NTFY_AGENTS_CHANNEL="agents-topic"
export NTFY_OPERATOR_TOPIC="operator-topic"
beszel_agent_public_key="$(<"$ssh_key.pub")"
export BESZEL_AGENT_PUBLIC_KEY="$beszel_agent_public_key"
export BESZEL_SUPERUSER_EMAIL="emulation-beszel@example.invalid"
export BESZEL_SUPERUSER_PASSWORD="emulation-beszel-password"

export RESTIC_PASSWORD="emulation-restic-password-000000000000"
# A disposable key and SFTP receiver are provisioned inside the guest below.

ssh_guest() {
  # Never authenticate to an unrelated localhost listener, including a stale VM.
  if ! kill -0 "$qemu_pid" 2>/dev/null || ! ss -H -lntp 'sport = :2222' | grep -Fq "pid=$qemu_pid,"; then
    return 1
  fi
  ssh \
    -o LogLevel=ERROR \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$ssh_key" \
    -p 2222 \
    ansible@127.0.0.1 "$@"
}

wait_for_ssh() {
  for _ in $(seq 1 120); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      echo "ARM64 guest process exited before SSH became reachable" >&2
      tail -100 "$qemu_log" >&2
      return 1
    fi
    if ssh_guest true; then
      return 0
    fi
    sleep 2
  done
  echo "ARM64 guest did not become reachable" >&2
  tail -100 "$qemu_log" >&2
  return 1
}

wait_for_cloud_init() {
  for _ in $(seq 1 120); do
    if ssh_guest test -f /var/lib/cloud/instance/boot-finished; then
      sleep 3
      if ssh_guest true; then
        return 0
      fi
    fi
    sleep 2
  done
  echo "ARM64 guest cloud-init did not finish with stable SSH" >&2
  tail -100 "$qemu_log" >&2
  return 1
}

wait_for_dns() {
  for _ in $(seq 1 60); do
    if dig +time=2 +tries=1 @127.0.0.1 -p 8053 "${test_inventory_hostname}.hole" A; then
      return 0
    fi
    sleep 2
  done
  echo "Pi-hole DNS did not become reachable" >&2
  return 1
}
verify_dns_filtering() {
  local allowed
  local blocked

  blocked="$(dig +short +time=2 +tries=1 @127.0.0.1 -p 8053 doubleclick.net A | head -1)"
  allowed="$(dig +short +time=2 +tries=1 @127.0.0.1 -p 8053 example.com A | head -1)"
  [[ "$blocked" == "0.0.0.0" ]] || {
    echo "Expected doubleclick.net to be blocked, got '$blocked'" >&2
    return 1
  }
  [[ -n "$allowed" && "$allowed" != "0.0.0.0" ]] || {
    echo "Expected example.com to resolve normally, got '$allowed'" >&2
    return 1
  }
}

wait_for_https() {
  for _ in $(seq 1 60); do
    if curl --fail --insecure --silent --max-time 5 --output /dev/null \
      --resolve "${pihole_hostname}:9443:127.0.0.1" \
      "https://${pihole_hostname}:9443/admin/"; then
      return 0
    fi
    sleep 2
  done
  echo "Caddy HTTPS did not proxy the Pi-hole administration UI" >&2
  return 1
}

verify_https_contract() {
  local redirect_status
  local proxy_headers
  local proxy_status
  local unknown_status

  redirect_status="$(curl --silent --max-time 10 --output /dev/null --write-out '%{http_code}' \
    --resolve "${pihole_hostname}:8080:127.0.0.1" \
    "http://${pihole_hostname}:8080/admin/")"
  proxy_headers="$state_dir/proxy-headers"
  proxy_status="$(curl --insecure --silent --max-time 10 --output /dev/null \
    --dump-header "$proxy_headers" --write-out '%{http_code}' \
    --resolve "${pihole_hostname}:9443:127.0.0.1" \
    "https://${pihole_hostname}:9443/admin/")"
  unknown_status="$(curl --insecure --silent --max-time 10 --output /dev/null --write-out '%{http_code}' \
    --resolve "${unknown_hostname}:9443:127.0.0.1" \
    "https://${unknown_hostname}:9443/")"

  if [[ "$redirect_status" != "308" ]]; then
    echo "Expected HTTP-to-HTTPS 308, got $redirect_status" >&2
    return 1
  fi
  if [[ "$proxy_status" != "302" ]]; then
    echo "Expected Pi-hole HTTPS redirect status 302, got $proxy_status" >&2
    return 1
  fi
  if ! grep -Eqi '^location: /admin/login' "$proxy_headers"; then
    echo "HTTPS proxy response did not contain Pi-hole's login redirect" >&2
    return 1
  fi
  if [[ "$unknown_status" != "404" ]]; then
    echo "Expected unknown HTTPS host status 404, got $unknown_status" >&2
    return 1
  fi
}

vm_phase wait-for-guest
wait_for_ssh
wait_for_cloud_init

# A real, isolated receiver exercises SSH authentication, chroot, restic init,
# backup, and restore without sending any fixture data to production storage.
vm_phase provision-backup-fixture
ssh_guest sudo bash -s <<'GUEST_BACKUP_SETUP'
set -euo pipefail
id backup-test >/dev/null 2>&1 || useradd --system --home-dir /var/lib/pi-backup-test --no-create-home --shell /usr/sbin/nologin --password '*' backup-test
install -d -m 0755 -o root -g root /var/lib/pi-backup-test
install -d -m 0700 -o backup-test -g backup-test /var/lib/pi-backup-test/pihole
[[ -f /root/pi-backup-test-key ]] || ssh-keygen -q -t ed25519 -N '' -f /root/pi-backup-test-key
install -m 0644 /root/pi-backup-test-key.pub /etc/ssh/pi-backup-test-authorized-key
cat >/etc/ssh/sshd_config.d/90-pi-backup-test.conf <<'SSHD_BACKUP_TEST'
Match User backup-test
  AuthorizedKeysFile /etc/ssh/pi-backup-test-authorized-key
  ChrootDirectory /var/lib/pi-backup-test
  ForceCommand internal-sftp -d /
  DisableForwarding yes
  PermitTTY no
  PasswordAuthentication no
Match all
SSHD_BACKUP_TEST
sshd -t
systemctl reload ssh
GUEST_BACKUP_SETUP
# Reload completion can precede the new listener becoming ready under TCG.
wait_for_ssh
RESTIC_SSH_PRIVATE_KEY="$(ssh_guest sudo cat /root/pi-backup-test-key)"
export RESTIC_SSH_PRIVATE_KEY
backup_host_key="$(ssh_guest sudo cat /etc/ssh/ssh_host_ed25519_key.pub)"
backup_test_vars="$state_dir/backup-test-vars.json"
jq -n --arg key "$backup_host_key" '{
  pi_backup_enabled: true,
  pi_backup_target_address: "127.0.0.1",
  pi_backup_target_host: "pi-backup-test.invalid",
  pi_backup_target_user: "backup-test",
  pi_backup_repository_prefix: "",
  pi_backup_target_known_host: ("pi-backup-test.invalid " + ($key | split(" ") | .[0:2] | join(" ")))
}' >"$backup_test_vars"

vm_phase enabled-first-convergence
vm_run_logged enabled-first.log ansible-playbook -i src/infra/pi/inventory/test.yml -e "@$backup_test_vars" src/infra/pi/playbooks/pi.yml
vm_phase enabled-second-convergence
vm_run_logged enabled-second.log ansible-playbook -i src/infra/pi/inventory/test.yml -e "@$backup_test_vars" src/infra/pi/playbooks/pi.yml
if ! grep -Eq 'changed=0 +unreachable=0 +failed=0' "$attempt_dir/enabled-second.log"; then
  echo "Second convergence was not idempotent" >&2
  exit 1
fi
vm_phase verify-backup-restore

# Verify a restored configuration has the same bytes as its source and that
# SFTP cannot read the guest filesystem outside its namespace.
ssh_guest sudo bash -s <<'GUEST_BACKUP_VERIFY'
set -euo pipefail
restore_result=$(/usr/local/libexec/pi-restic-restore-disposable pihole)
printf '%s\n' "$restore_result"
restored=${restore_result##*restore available in disposable directory: }
[[ "$restored" == /var/lib/pi-restic-restore/* && -d "$restored" ]]
cmp /opt/pihole/dnsmasq.d/05-homelab-local-records.conf "$restored/opt/pihole/dnsmasq.d/05-homelab-local-records.conf"
if printf 'get /../../etc/passwd /tmp/pi-backup-escaped
' | sftp -b - \
  -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o HostKeyAlias=pi-backup-test.invalid -o UserKnownHostsFile=/etc/restic/target_known_hosts \
  -i /root/pi-backup-test-key backup-test@127.0.0.1; then
  echo 'SFTP escaped its repository namespace' >&2
  exit 1
fi
[[ ! -e /tmp/pi-backup-escaped ]]
GUEST_BACKUP_VERIFY

wait_for_dns
verify_dns_filtering
wait_for_https
verify_https_contract

# Retiring backups must work without credentials and preserve recovery data.
# Save fixture-only checksums in the guest; never emit credential contents.
ssh_guest sudo bash -s <<'GUEST_BACKUP_PRESERVE'
set -euo pipefail
find /etc/restic /var/lib/pi-restic /var/lib/pi-restic-restore /var/lib/pi-backup-test \
  -type f -print0 | sort -z | xargs -0 sha256sum >/root/backup-preservation.sha256
[[ -s /root/backup-preservation.sha256 ]]
GUEST_BACKUP_PRESERVE
unset RESTIC_PASSWORD RESTIC_SSH_PRIVATE_KEY
# Re-run only the changed retirement boundary; the complete appliance already
# converged twice above, and its network services remain live for reboot checks.
# Keep this playbook checked in so the Pi check validates the exact fixture used
# by the disposable VM.
readonly disable_playbook="src/infra/pi/tests/vm/disable-backups.yml"
vm_phase disabled-first-convergence
vm_run_logged disabled-first.log ansible-playbook -i src/infra/pi/inventory/test.yml -e '{"pi_backup_enabled":false}' "$disable_playbook"
vm_phase disabled-second-convergence
vm_run_logged disabled-second.log ansible-playbook -i src/infra/pi/inventory/test.yml -e '{"pi_backup_enabled":false}' "$disable_playbook"
if ! grep -Eq 'changed=0 +unreachable=0 +failed=0' "$attempt_dir/disabled-second.log"; then
  echo "Second disabled convergence was not idempotent" >&2
  exit 1
fi

verify_backups_disabled() {
  ssh_guest sudo bash -s <<'GUEST_BACKUP_DISABLED'
set -euo pipefail
sha256sum --check --status /root/backup-preservation.sha256
if systemctl list-unit-files --no-legend 'pi-restic-*' | grep -q .; then
  echo 'Pi backup unit files survived disabled convergence' >&2
  exit 1
fi
if systemctl list-units --state=active --no-legend 'pi-restic-*' | grep -q .; then
  echo 'Pi backup units remain active' >&2
  exit 1
fi
if find /usr/local/libexec -maxdepth 1 -name 'pi-restic-*' -print | grep -q .; then
  echo 'Pi backup helpers survived disabled convergence' >&2
  exit 1
fi
GUEST_BACKUP_DISABLED
}
verify_backups_disabled

vm_phase reboot-and-verify
ssh_guest sudo systemctl reboot || true
for _ in $(seq 1 30); do
  if ! ssh_guest true; then
    break
  fi
  sleep 1
done
wait_for_ssh
wait_for_dns
verify_dns_filtering
wait_for_https
verify_https_contract

verify_backups_disabled
vm_phase complete
