#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
readonly script_dir repo_root

fake_bin="$(mktemp -d)"
known_hosts="$(mktemp)"
output="$(mktemp)"
cleanup() {
  rm -rf "$fake_bin" "$known_hosts" "$output"
}
trap cleanup EXIT

cp "$script_dir/fixtures/nix" "$fake_bin/nix"
chmod 0755 "$fake_bin/nix"

cat >"$fake_bin/ansible-inventory" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"pi_appliances":{"hosts":["pi"]},"_meta":{"hostvars":{"pi":{"ansible_host":"192.168.1.225","ansible_user":"nori"}}}}
JSON
EOF

cat >"$fake_bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
[[ ${FAKE_PIN_FAIL:-0} != 1 ]]
EOF

cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
[[ ${FAKE_SSH_FAIL:-0} != 1 ]] || exit 42
args=" $* "
[[ $args == *" -o BatchMode=yes "* ]]
[[ $args == *" -o ConnectTimeout=10 "* ]]
[[ $args == *" -o StrictHostKeyChecking=yes "* ]]
[[ $args == *" -o UserKnownHostsFile="* ]]
[[ $args == *" nori@192.168.1.225 sudo --non-interactive podman exec caddy cat /etc/caddy/Caddyfile "* ]]
cat <<'CADDY'
{
  admin off
}
*.home.example {
  @books {
    host books.home.example
  }
  @media {
    host media.home.example
  }
}
CADDY
EOF
chmod 0755 "$fake_bin/ansible-inventory" "$fake_bin/ssh-keygen" "$fake_bin/ssh"

printf '192.168.1.225 ssh-ed25519 fixture\n' >"$known_hosts"

PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$script_dir/fixtures/inventory.json" \
  PI_SSH_KNOWN_HOSTS="$known_hosts" \
  PIHOLE_WEB_PASSWORD='' \
  "$repo_root/infra/pi/scripts/run-production.sh" inspect-caddy >"$output"

hosts="$("$repo_root/infra/pi/scripts/caddy-hosts.sh" <"$output")"
[[ $hosts == $'books.home.example\nmedia.home.example' ]]
if grep -qx 'missing.home.example' <<<"$hosts"; then
  echo "Caddy host projection invented a missing route" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$script_dir/fixtures/inventory.json" \
  PI_SSH_KNOWN_HOSTS='' \
  "$repo_root/infra/pi/scripts/run-production.sh" inspect-caddy >/dev/null 2>&1; then
  echo "Caddy inspection accepted a missing host-key pin" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$script_dir/fixtures/inventory.json" \
  PI_SSH_KNOWN_HOSTS="$known_hosts" \
  FAKE_PIN_FAIL=1 \
  "$repo_root/infra/pi/scripts/run-production.sh" inspect-caddy >/dev/null 2>&1; then
  echo "Caddy inspection accepted a rejected host-key pin" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" \
  INVENTORY_FIXTURE="$script_dir/fixtures/inventory.json" \
  PI_SSH_KNOWN_HOSTS="$known_hosts" \
  FAKE_SSH_FAIL=1 \
  "$repo_root/infra/pi/scripts/run-production.sh" inspect-caddy >/dev/null 2>&1; then
  echo "Caddy inspection swallowed an SSH transport failure" >&2
  exit 1
fi

echo "production Caddy inspection contract: PASS"
