#!/usr/bin/env bash
set -euo pipefail

role_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly role_dir
readonly template_file="$role_dir/templates/Caddyfile.j2"
readonly tasks_file="$role_dir/tasks/main.yml"

fail() {
  echo "caddy role contract: $*" >&2
  exit 1
}

[[ -f "$template_file" ]] || fail "Caddyfile template is missing"
[[ -f "$tasks_file" ]] || fail "Caddy role tasks are missing"

rg -q 'Validate the inventory-derived Caddy route contract' "$tasks_file" \
  || fail "route contract validation is missing"
rg -q 'refusing to render a potentially unsafe proxy' "$tasks_file" \
  || fail "unsafe route failure message is missing"
rg -q 'Validate the Caddy domain contract' "$tasks_file" \
  || fail "domain contract validation is missing"
rg -Fq "reject('match', '^/[^\\\\s{}]*$')" "$tasks_file" \
  || fail "forward-auth paths are not constrained against directive injection"
rg -q 'upstream_origin_header is match' "$tasks_file" \
  || fail "upstream Origin values are not constrained"

rg -q 'route\.hostname' "$template_file" \
  || fail "inventory-derived host matching is missing"
rg -q 'pi_deprecated_domains' "$template_file" \
  || fail "deprecated-domain inventory input is missing"
rg -q 'header_regexp Host' "$template_file" \
  || fail "deprecated-domain host matcher is missing"
rg -q 'redir @legacySubdomain https://\{re\.legacySubdomain\.1\}' "$template_file" \
  || fail "deprecated-domain redirect is missing"
rg -Fq "route.reachability | default('internal') == 'internal'" "$template_file" \
  || fail "internal reachability gate is missing"
rg -Fq "route.auth | default('none') == 'forward-auth'" "$template_file" \
  || fail "forward-auth route selection is missing"
rg -q 'route\.forward_auth_exempt_paths' "$template_file" \
  || fail "forward-auth path exemptions are missing"
rg -q 'forward_auth_exempt_paths is not string' "$tasks_file" \
  || fail "string forward-auth path exemptions are not rejected"
rg -q 'forward_auth .*route\.forward_auth_upstream' "$template_file" \
  || fail "forward-auth upstream is not inventory-derived"
rg -q 'uri /api/verify\?rd=https://auth\.' "$template_file" \
  || fail "Authelia verification endpoint is missing"
rg -q 'copy_headers Remote-User Remote-Email Remote-Name Remote-Groups' "$template_file" \
  || fail "Authelia identity headers are not propagated"
rg -q 'route\.scheme.*route\.upstream_address.*route\.upstream_port' "$template_file" \
  || fail "scheme-aware reverse proxy target is missing"
rg -q 'header_up Host' "$template_file" \
  || fail "optional upstream Host rewrite is missing"
rg -q 'respond 404' "$template_file" \
  || fail "unknown hosts do not fail closed"

echo "caddy role contract: PASS"
