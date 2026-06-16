#!/usr/bin/env bash
#
# Repo-convention enforcement. Each rule below is a hard constraint,
# not a suggestion: the convention is whatever the check enforces.
# Adding a deliberate exception means editing this rule, not just
# bypassing it. Patterns are `grep -rn` and intentionally simple —
# anything that needs AST-aware checking should graduate to a
# tree-sitter-nix wrapper.
#
# Invoked by flake.nix `checks.${system}.forbidden-patterns`. Run by
# hand against a checkout root:
#
#   bash scripts/checks/forbidden-patterns.sh .
#
# Exits 0 on success, 1 on any rule violation.

set -u
cd "${1:?usage: forbidden-patterns.sh <source-root>}"
fail=0

# No inline PBKDF2 client_secret hashes anywhere in modules.
# OIDC client hashes live only in sops as
# oidc-<n>-client-secret-hash; Authelia reads them via the
# template config-filter (see modules/services/authelia.nix).
if grep -rn '\$pbkdf2-' modules/ ; then
  echo
  echo "✗ Inline pbkdf2 hashes found above. OIDC hashes belong in sops"
  echo "  (key: oidc-<n>-client-secret-hash). See"
  echo "  .claude/skills/add-oidc-client/ for the bootstrap workflow."
  fail=1
fi

# The `clientSecretHash` field was removed from the lanRoutes
# oidc submodule when the template-filter migration landed —
# any reference is stale.
if grep -rn 'clientSecretHash' modules/ ; then
  echo
  echo "✗ clientSecretHash field references found. The field was"
  echo "  removed; hashes live in sops as oidc-<n>-client-secret-hash."
  fail=1
fi

# Caddy vhost declarations must come from
# modules/effects/lan-route.nix only — nori.lanRoutes is the
# single source of truth for *.<nori.domain> exposure.
# modules/services/caddy.nix is exempt because it carries
# the transitional `*.nori.lan` → `*.<nori.domain>` 301
# redirect vhost from ADR-0004 (drop the exemption when
# that redirect goes away).
if grep -rln 'services\.caddy\.virtualHosts' modules/ \
   | grep -vE '^modules/effects/lan-route\.nix$|^modules/services/caddy\.nix$' ; then
  echo
  echo "✗ Direct services.caddy.virtualHosts found above. Use"
  echo "  nori.lanRoutes.<name> = { port = N; }; instead — the"
  echo "  abstraction generates Caddy + Blocky + Gatus together."
  fail=1
fi

# Blocky customDNS mappings — same single-source rule.
if grep -rln 'services\.blocky\.settings\.customDNS' modules/ \
   | grep -v '^modules/effects/lan-route\.nix$' ; then
  echo
  echo "✗ Direct services.blocky.settings.customDNS found above."
  echo "  Use nori.lanRoutes.<name> instead."
  fail=1
fi

# Caddy's internal CA is enabled via globalConfig =
# "local_certs", not via acmeCA = "internal" — Caddy will
# literally try to dial `internal` as an ACME directory URL
# and fail. See .claude/skills/gotcha-caddy-acme-internal/
if grep -rn 'acmeCA = "internal"' modules/ ; then
  echo
  echo "✗ acmeCA = \"internal\" found above. Caddy interprets this"
  echo "  as a literal ACME directory URL. Use:"
  echo '    services.caddy.globalConfig = "local_certs";'
  fail=1
fi

# Gatus's ntfy alerting provider takes `url` and `topic` as
# SEPARATE fields. Embedding the topic in the URL silently
# disables alerting (logs "Ignoring provider=ntfy due to
# error=topic not set" once at startup, then nothing).
# See .claude/skills/gotcha-gatus-ntfy-provider/
if grep -rn 'url = "https://ntfy.sh/' modules/ ; then
  echo
  echo "✗ Gatus ntfy URL with embedded topic found above. Split into"
  echo "  separate fields:"
  echo '    alerting.ntfy.url   = "https://ntfy.sh";'
  echo "    alerting.ntfy.topic = \"\${NTFY_CHANNEL}\";"
  fail=1
fi

# Tailnet IP literals (CGNAT 100.64.0.0/10) outside flake.nix's
# identityFor are stale before the next topology change. Cross-
# host references go through the topology registry:
# `config.nori.hosts.<host>.tailnetIp`. flake.nix is the only
# legitimate site for the host-specific literal.
#
# Allowlist:
#   * 100.100.100.100  Tailscale MagicDNS stub (well-known
#                      constant, not a host)
#   * 100.64.0.0/10    CGNAT range (network spec, not a host —
#                      legitimate in firewall ACLs)
#   * modules/effects/hosts.nix  registry schema's own header
#                                comment narrates the refactor
if grep -rEn '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+\b' \
     modules/ \
   | grep -vE '100\.100\.100\.100|100\.64\.0\.0/10' \
   | grep -v '^modules/effects/hosts\.nix:' ; then
  echo
  echo "✗ Tailnet IP literal (CGNAT range) found above. Use"
  echo "  config.nori.hosts.<host>.tailnetIp from the topology"
  echo "  registry. Schema: modules/effects/hosts.nix; values:"
  echo "  flake.nix identityFor."
  fail=1
fi

# Literal `*.nori.lan` URIs are stale: ADR-0004 made
# `${nori.domain}` (= home.phibkro.org) the canonical
# parent, with `*.nori.lan` kept only as a transitional
# 301-redirect target until family bookmarks migrate.
# Two systems care about the URI exactly:
#
#   1. Authelia OIDC `redirect_uris` — exact-string
#      matched at the IdP; embedding `.nori.lan` here
#      silently rejects every SSO redirect from the
#      canonical domain (caught 2026-06-12 in the
#      post-migration audit; fix at authelia.nix:22).
#   2. Service `root_url` / `BASE_URL` / cookie domain —
#      readers cache the value.
#
# Allowlist: caddy.nix carries the transitional 301
# redirect vhost; lan-route.nix's customDNS map emits
# both the transitional + canonical entries side by
# side. Both are temporary and named in their headers.
if grep -rEn '"https?://[a-z0-9.-]*\.nori\.lan' modules/ \
   | grep -vE '^modules/services/caddy\.nix:|^modules/effects/lan-route\.nix:' ; then
  echo
  echo "✗ Hard-coded https://*.nori.lan URI found above."
  echo "  Use \"https://\${name}.\${config.nori.domain}…\" — the"
  echo "  transitional alias is for the 301 redirect only,"
  echo "  not for IdP redirect_uris or service root URLs."
  fail=1
fi

# Migration-phase tokens (P\d+ prep|cutover|landing) decay
# the moment the phase lands. modules/ is for what the
# code does today, not what it's getting ready to do.
# Plans + reports + ADRs under docs/ are the
# right home for phase narration; flag anywhere else.
if grep -rEn '\bP[0-9]+ (prep|cutover|landing|migration)\b' \
     modules/ machines/ ; then
  echo
  echo "✗ Migration-phase token found above. Phase tokens"
  echo "  (P12 prep, P15 cutover, etc.) decay as soon as"
  echo "  the phase lands. Move the rationale into the"
  echo "  commit message; if it's load-bearing for future"
  echo "  context, put it in docs/."
  fail=1
fi

exit "$fail"
