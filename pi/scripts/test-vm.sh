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
readonly qemu_log="$state_dir/qemu.log"

mkdir -p "$cache_dir" "$state_dir"

if [[ ! -s "$base_image" ]]; then
  curl --fail --location --output "$base_image.part" "$image_url"
  mv "$base_image.part" "$base_image"
fi

rm -f "$overlay" "$seed" "$ssh_key" "$ssh_key.pub" "$qemu_log"
ssh-keygen -q -t ed25519 -N '' -f "$ssh_key"
qemu-img create -q -f qcow2 -F qcow2 -b "$base_image" "$overlay" 16G

sed "s|__SSH_PUBLIC_KEY__|$(<"$ssh_key.pub")|" \
  pi/tests/vm/user-data.yml > "$state_dir/user-data.yml"
cloud-localds \
  --network-config=pi/tests/vm/network-config.yml \
  "$seed" \
  "$state_dir/user-data.yml" \
  pi/tests/vm/meta-data.yml

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
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8053-:53,hostfwd=udp:127.0.0.1:8053-:53,hostfwd=tcp:127.0.0.1:8081-:8081,hostfwd=tcp:127.0.0.1:8080-:80,hostfwd=tcp:127.0.0.1:8443-:443" \
  -device virtio-net-pci,netdev=net0 \
  >"$qemu_log" 2>&1 &
readonly qemu_pid=$!
trap 'kill "$qemu_pid" 2>/dev/null || true' EXIT

export PI_VM_SSH_KEY="$ssh_key"
export PIHOLE_WEB_PASSWORD="emulation-only-password"

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
      --resolve pihole.home.phibkro.org:8443:127.0.0.1 \
      https://pihole.home.phibkro.org:8443/admin/; then
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
    --resolve pihole.home.phibkro.org:8443:127.0.0.1 \
    https://pihole.home.phibkro.org:8443/admin/)"
  unknown_status="$(curl --insecure --silent --max-time 10 --output /dev/null --write-out '%{http_code}' \
    --resolve unknown.home.phibkro.org:8443:127.0.0.1 \
    https://unknown.home.phibkro.org:8443/)"

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
