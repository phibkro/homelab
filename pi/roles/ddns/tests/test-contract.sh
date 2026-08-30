#!/usr/bin/env bash
set -euo pipefail

role_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$role_dir/templates/cloudflare-ddns.sh.j2"
test -f "$role_dir/tasks/main.yml"
test -f "$script"
test -f "$role_dir/templates/cloudflare-ddns.service.j2"
test -f "$role_dir/templates/cloudflare-ddns.timer.j2"
grep -Fq -- '--dry-run' "$script"
grep -Fq -- 'type:"A"' "$script"
grep -Fq -- 'proxied' "$script"
grep -Fq -- 'DELETE' "$script"
grep -Fq -- 'ProtectSystem=strict' "$role_dir/templates/cloudflare-ddns.service.j2"
grep -Fq -- 'User=cloudflare-ddns' "$role_dir/templates/cloudflare-ddns.service.j2"
grep -Fq -- 'LoadCredential=' "$role_dir/templates/cloudflare-ddns.service.j2"
grep -Fq -- 'content: "{{ ddns_api_token }}\n"' "$role_dir/tasks/main.yml"
grep -A7 -F -- 'name: Install the Cloudflare DDNS updater' "$role_dir/tasks/main.yml" \
  | grep -Fq -- 'group: cloudflare-ddns'
if grep -Fq -- 'content: "CLOUDFLARE_API_TOKEN={{ ddns_api_token }}' "$role_dir/tasks/main.yml"; then
  echo 'credentials file must contain the raw token consumed by LoadCredential' >&2
  exit 1
fi
grep -Fq -- 'ProtectControlGroups=true' "$role_dir/templates/cloudflare-ddns.service.j2"
grep -Fq -- 'RestrictSUIDSGID=true' "$role_dir/templates/cloudflare-ddns.service.j2"
grep -Fq -- 'SystemCallFilter=@system-service' "$role_dir/templates/cloudflare-ddns.service.j2"
grep -Fq -- 'fail-with-body' "$script"
grep -Fq -- 'not ddns_enabled' "$role_dir/tasks/main.yml"
grep -Fq -- 'state: absent' "$role_dir/tasks/main.yml"
grep -Fq -- 'page=' "$role_dir/templates/cloudflare-ddns.sh.j2"
grep -Fq -- 'ddns_credentials.changed | default(false)' "$role_dir/tasks/main.yml"
grep -Fq -- 'ddns_timer.changed | default(false)' "$role_dir/tasks/main.yml"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
install -m 0755 "$script" "$tmp_dir/cloudflare-ddns"

cat > "$tmp_dir/mock-curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=''; url=''; method=GET
while (($#)); do
  case "$1" in
    -o|--output) output=$2; shift 2 ;;
    -X|--request) method=$2; shift 2 ;;
    --data|--data-raw) shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
printf '%s %s\n' "$method" "$url" >>"${DDNS_MOCK_LOG:?}"
if [[ "$url" == *api.ipify.org* ]]; then
  body=${DDNS_MOCK_IP:-8.8.8.8}
elif [[ "$url" == *'/zones?'* ]]; then
  body='{"success":true,"result":[{"id":"0123456789abcdef0123456789abcdef"}]}'
elif [[ "$url" == *'/dns_records?type=A&'* ]]; then
  if [[ "${DDNS_MOCK_SCENARIO:-}" == cleanup ]]; then
    body='{"success":true,"result":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","type":"A","name":"stale.home.example.test","content":"8.8.8.8","ttl":1,"proxied":false,"comment":"Managed by homelab internet route"},{"id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","type":"A","name":"keep.home.example.test","content":"8.8.8.8","ttl":1,"proxied":false,"comment":"manual record"}],"result_info":{"page":1,"per_page":100,"total_pages":1,"total_count":2}}'
  else
    body='{"success":true,"result":[],"result_info":{"page":1,"per_page":100,"total_pages":1,"total_count":0}}'
  fi
elif [[ "$url" == *'/dns_records?'* ]]; then
  case "${DDNS_MOCK_SCENARIO:-}" in
    update) body='{"success":true,"result":[{"id":"cccccccccccccccccccccccccccccccc","type":"A","name":"public.home.example.test","content":"1.1.1.1","ttl":1,"proxied":false,"comment":"Managed by homelab internet route"}]}' ;;
    malformed) body='{"success":true,"result":[{"id":"bad","type":"A","name":"public.home.example.test","content":"1.1.1.1","ttl":1,"proxied":false,"comment":"Managed by homelab internet route"}]}' ;;
    noop) body='{"success":true,"result":[{"id":"cccccccccccccccccccccccccccccccc","type":"A","name":"public.home.example.test","content":"8.8.8.8","ttl":1,"proxied":false,"comment":"Managed by homelab internet route"}]}' ;;
    unmanaged) body='{"success":true,"result":[{"id":"cccccccccccccccccccccccccccccccc","type":"A","name":"public.home.example.test","content":"1.1.1.1","ttl":1,"proxied":false,"comment":"manual record"}]}' ;;
    *) body='{"success":true,"result":[]}' ;;
  esac
elif [[ "$url" == *'/dns_records/'* || "$url" == *'/dns_records' ]]; then
  body='{"success":true,"result":{"id":"cccccccccccccccccccccccccccccccc"}}'
else
  echo "unexpected URL: $url" >&2; exit 1
fi
if [[ -n "$output" ]]; then printf '%s' "$body" >"$output"; printf '200'; else printf '%s' "$body"; fi
EOF
chmod 0755 "$tmp_dir/mock-curl"

run_case() {
  local scenario=$1 mode=$2 desired=${3:-'["public.home.example.test"]'}
  : >"$tmp_dir/mock.log"
  DDNS_MOCK_SCENARIO=$scenario DDNS_MOCK_LOG="$tmp_dir/mock.log" \
  CLOUDFLARE_API_TOKEN=01234567890123456789012345678901 \
  DDNS_ZONE_NAME=home.example.test DDNS_HOSTNAMES_JSON="$desired" \
  DDNS_MANAGED_COMMENT='Managed by homelab internet route' \
  DDNS_PUBLIC_IPV4_URL=https://api.ipify.org DDNS_API_BASE_URL=https://api.cloudflare.com/client/v4 \
  DDNS_TTL=1 DDNS_PROXIED=false DDNS_CURL_BIN="$tmp_dir/mock-curl" \
  "$tmp_dir/cloudflare-ddns" "$mode"
}

grep -Fq 'would create public.home.example.test -> 8.8.8.8' <<<"$(run_case create --dry-run)"
run_case create --apply >/dev/null
grep -Eq '^POST .*dns_records' "$tmp_dir/mock.log"
grep -Fq 'would update public.home.example.test -> 8.8.8.8' <<<"$(run_case update --dry-run)"
run_case update --apply >/dev/null
grep -Eq '^PUT .*dns_records/' "$tmp_dir/mock.log"
grep -Fq 'unchanged public.home.example.test -> 8.8.8.8' <<<"$(run_case noop --dry-run)"
grep -Eq '^(POST|PUT|DELETE) ' "$tmp_dir/mock.log" && exit 1
if run_case unmanaged --dry-run >/dev/null 2>&1; then exit 1; fi
if run_case malformed --dry-run >/dev/null 2>&1; then exit 1; fi
if DDNS_MOCK_IP=192.168.1.10 run_case create --dry-run >/dev/null 2>&1; then exit 1; fi
if DDNS_MOCK_IP=192.0.0.1 run_case create --dry-run >/dev/null 2>&1; then exit 1; fi
if DDNS_MOCK_IP=192.0.0.8 run_case create --dry-run >/dev/null 2>&1; then exit 1; fi
if DDNS_MOCK_IP=192.0.0.170 run_case create --dry-run >/dev/null 2>&1; then exit 1; fi
cleanup_output=$(run_case cleanup --cleanup '[]')
grep -Fq 'removed stale.home.example.test (owned stale A record)' <<<"$cleanup_output"
grep -Eq '^DELETE .*dns_records/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$tmp_dir/mock.log"
grep -Fq 'dns_records/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' "$tmp_dir/mock.log" && exit 1
grep -Fq 'api.ipify.org' "$tmp_dir/mock.log" && exit 1
echo 'ok - ddns create/update/no-op/ownership/IP/cleanup contract'
