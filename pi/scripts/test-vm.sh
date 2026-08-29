#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly repo_root
cd "$repo_root"

readonly cache_dir="${TMPDIR:-/tmp}/homelab-pi-cache"
readonly state_dir="${TMPDIR:-/tmp}/homelab-pi-vm"
readonly image_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2"
readonly base_image="$cache_dir/debian-12-genericcloud-arm64.qcow2"
readonly overlay="$state_dir/root.qcow2"
readonly seed="$state_dir/seed.img"
readonly ssh_key="$state_dir/id_ed25519"
readonly authelia_issuer_key="$state_dir/authelia-issuer-rsa"
readonly qemu_log="$state_dir/qemu.log"
readonly ansible_log="$state_dir/ansible.log"
readonly reuse_vm="${PI_VM_REUSE:-false}"
readonly keep_vm_on_failure="${PI_VM_KEEP_ON_FAILURE:-false}"

mkdir -p "$cache_dir" "$state_dir"

if [[ ! -s "$base_image" ]]; then
  curl --fail --location --output "$base_image.part" "$image_url"
  mv "$base_image.part" "$base_image"
fi

if [[ "$reuse_vm" == true ]]; then
  for artifact in "$overlay" "$seed" "$ssh_key" "$authelia_issuer_key"; do
    if [[ ! -s "$artifact" ]]; then
      echo "Cannot reuse the ARM64 guest; missing artifact: $artifact" >&2
      exit 1
    fi
  done
  rm -f "$qemu_log" "$ansible_log"
else
  rm -f "$overlay" "$seed" "$ssh_key" "$ssh_key.pub" "$authelia_issuer_key" "$qemu_log" "$ansible_log"
  ssh-keygen -q -t ed25519 -N '' -f "$ssh_key"
  ssh-keygen -q -t rsa -b 2048 -m PEM -N '' -f "$authelia_issuer_key"
  qemu-img create -q -f qcow2 -F qcow2 -b "$base_image" "$overlay" 16G

  sed "s|__SSH_PUBLIC_KEY__|$(<"$ssh_key.pub")|" \
    pi/tests/vm/user-data.yml > "$state_dir/user-data.yml"
  cloud-localds \
    --network-config=pi/tests/vm/network-config.yml \
    "$seed" \
    "$state_dir/user-data.yml" \
    pi/tests/vm/meta-data.yml
fi

qemu_prefix="$(dirname "$(dirname "$(readlink -f "$(command -v qemu-system-aarch64)")")")"
readonly qemu_prefix
readonly firmware="$qemu_prefix/share/qemu/edk2-aarch64-code.fd"
if [[ ! -f "$firmware" ]]; then
  echo "ARM64 UEFI firmware not found at $firmware" >&2
  exit 1
fi

qemu-system-aarch64 \
  -machine virt,accel=tcg \
  -cpu cortex-a72 \
  -smp 4 \
  -m 3072 \
  -nographic \
  -bios "$firmware" \
  -drive "if=virtio,format=qcow2,file=$overlay" \
  -drive "if=virtio,format=raw,readonly=on,file=$seed" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8053-:53,hostfwd=udp:127.0.0.1:8053-:53,hostfwd=tcp:127.0.0.1:8081-:8081,hostfwd=tcp:127.0.0.1:8080-:80,hostfwd=tcp:127.0.0.1:9443-:443" \
  -device virtio-net-pci,netdev=net0 \
  >"$qemu_log" 2>&1 &
readonly qemu_pid=$!
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 && "$keep_vm_on_failure" == true ]]; then
    echo "ARM64 guest preserved after failure (PID $qemu_pid, SSH port 2222)" >&2
    return
  fi
  kill "$qemu_pid" 2>/dev/null || true
}
trap cleanup EXIT

export PI_VM_SSH_KEY="$ssh_key"
export ANSIBLE_LOG_PATH="$ansible_log"
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
export RESTIC_PASSWORD="emulation-restic-password-000000000000"
export RESTIC_SSH_PRIVATE_KEY='-----BEGIN OPENSSH PRIVATE KEY-----
emulation-only
-----END OPENSSH PRIVATE KEY-----'

ssh_guest() {
  ssh -q \
    -o BatchMode=yes \
    -o ConnectTimeout=2 \
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
    if dig +time=2 +tries=1 @127.0.0.1 -p 8053 pi.hole A; then
      return 0
    fi
    sleep 2
  done
  echo "Pi-hole DNS did not become reachable" >&2
  return 1
}

wait_for_https() {
  for _ in $(seq 1 60); do
    if curl --fail --insecure --silent --max-time 5 --output /dev/null \
      --resolve pihole.home.phibkro.org:9443:127.0.0.1 \
      https://pihole.home.phibkro.org:9443/admin/; then
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
    --resolve pihole.home.phibkro.org:8080:127.0.0.1 \
    http://pihole.home.phibkro.org:8080/admin/)"
  proxy_headers="$state_dir/proxy-headers"
  proxy_status="$(curl --insecure --silent --max-time 10 --output /dev/null \
    --dump-header "$proxy_headers" --write-out '%{http_code}' \
    --resolve pihole.home.phibkro.org:9443:127.0.0.1 \
    https://pihole.home.phibkro.org:9443/admin/)"
  unknown_status="$(curl --insecure --silent --max-time 10 --output /dev/null --write-out '%{http_code}' \
    --resolve unknown.home.phibkro.org:9443:127.0.0.1 \
    https://unknown.home.phibkro.org:9443/)"

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

wait_for_ssh
wait_for_cloud_init

ansible-playbook -i pi/inventory/test.yml pi/playbooks/pi.yml
second_run="$(ansible-playbook -i pi/inventory/test.yml pi/playbooks/pi.yml)"
printf '%s\n' "$second_run"
if ! grep -Eq 'changed=0 +unreachable=0 +failed=0' <<<"$second_run"; then
  echo "Second convergence was not idempotent" >&2
  exit 1
fi

wait_for_dns
wait_for_https
verify_https_contract

ssh_guest sudo systemctl reboot || true
for _ in $(seq 1 30); do
  if ! ssh_guest true; then
    break
  fi
  sleep 1
done
wait_for_ssh
wait_for_dns
wait_for_https
verify_https_contract
