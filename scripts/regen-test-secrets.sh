#!/usr/bin/env bash
# Regenerate the homelab's test age key + test sops file.
#
# These files are INTENTIONALLY committed in plaintext (key) and in
# sops form (secrets). They are scoped to the nixosTest VM — the
# production secrets in secrets/secrets.yaml are encrypted to a
# DIFFERENT recipient set (mac/workstation/pi/aurora/pavilion) that
# this test key is not a member of, so leaking this file leaks
# nothing real.
#
# Run when:
#   - first bootstrap
#   - you want to refresh the test secrets shape (added a new field,
#     rotated the test user's password, etc)
#
# The script is idempotent — re-running overwrites. It produces:
#   tests/keys/test-age.txt           plaintext age key (private)
#   tests/keys/test-age.pub           the public part
#   tests/secrets/test.yaml           sops-encrypted secrets for the
#                                     e2e VM (includes authelia +
#                                     restic-password)
#
# Test user credentials (for manual probing of the auth flow):
#   username: nori
#   password: test-password-do-not-use-in-prod

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

KEY_FILE="tests/keys/test-age.txt"
PUB_FILE="tests/keys/test-age.pub"
SECRETS_FILE="tests/secrets/test.yaml"
SOPS_CONFIG="tests/.sops.yaml"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing tool: $1"
    echo "hint: run inside \`nix shell nixpkgs#age nixpkgs#sops nixpkgs#openssl nixpkgs#libargon2 nixpkgs#python3 -c bash $0\`"
    exit 1
  }
}
for t in age-keygen sops openssl argon2 python3 authelia ssh-keygen; do need "$t"; done

echo "==> generating test age key → $KEY_FILE"
rm -f "$KEY_FILE"
age-keygen -o "$KEY_FILE" 2>/dev/null
PUB="$(grep -oE 'age1[a-z0-9]+' "$KEY_FILE" | tail -1)"
{
  echo "# test-only age public key — corresponds to $KEY_FILE"
  echo "# committed; safe to share; cannot decrypt production secrets"
  echo "$PUB"
} > "$PUB_FILE"
echo "    public key: $PUB"

echo "==> refreshing $SOPS_CONFIG with new recipient"
cat > "$SOPS_CONFIG" <<EOF
# sops policy scoped to tests/ — the test age recipient cannot decrypt
# anything outside this subtree, and the production .sops.yaml does not
# include this key. The two configs are isolated by design.
#
# Refresh the recipient by re-running scripts/regen-test-secrets.sh; the
# script writes the same public key into both this file and
# tests/keys/test-age.pub.
#
# Use this config explicitly via \`sops --config tests/.sops.yaml ...\`
# — sops walks up to the repo root by default and would otherwise pick
# up the production .sops.yaml first.

keys:
  - &test $PUB

creation_rules:
  - path_regex: \.yaml\$
    key_groups:
      - age:
          - *test
EOF

# Prepend a banner to the private key file so anyone who opens it
# immediately sees this is test data, not a leaked prod key.
TMP_KEY="$(mktemp)"
{
  echo "# TEST KEY — DO NOT USE IN PRODUCTION."
  echo "# Committed in plaintext on purpose. The homelab production sops"
  echo "# files are encrypted to a different recipient set and cannot"
  echo "# be opened by this key. See scripts/regen-test-secrets.sh."
  cat "$KEY_FILE"
} > "$TMP_KEY"
mv "$TMP_KEY" "$KEY_FILE"

echo "==> generating authelia secrets"
JWT="$(openssl rand -hex 32)"
SESSION="$(openssl rand -hex 32)"
STORAGE="$(openssl rand -hex 32)"
HMAC="$(openssl rand -hex 32)"
RESTIC_PASS="$(openssl rand -hex 16)"
# restic-ssh-key: SSH private key used by workstation's restic units
# to talk to aurora's chrooted SFTP target. Tests don't actually run
# restic; the secret just needs to satisfy sops-install-secrets's
# manifest check. Use a real ed25519 key to keep the shape honest.
RESTIC_SSH_KEY="$(ssh-keygen -t ed25519 -N '' -q -f /tmp/_test_restic_key -C 'test-only' && cat /tmp/_test_restic_key && rm -f /tmp/_test_restic_key /tmp/_test_restic_key.pub)"
# Caddy's cloudflare-acme-token — test value (cf API never dialed in
# the VM since caddy uses local_certs there). The key MUST exist
# because modules/infra/networking/caddy.nix declares the sops secret
# unconditionally when nori.services.caddy is enabled.
CF_ACME_TOKEN="test-cloudflare-token-not-real"
# gatus-env: sourced as a systemd EnvironmentFile by the gatus service.
# Must parse as KEY=VALUE lines (a `#` comment line is also valid empty
# content).
GATUS_ENV="# gatus test env — intentionally empty (no SMTP etc)"
# heartbeat-pi-url: read by heartbeat.service (curls the URL once per
# minute). The curl will fail since this is a stub URL — but the
# service is a oneshot, so the failure doesn't break the timer activation
# we actually assert in testScript.
HEARTBEAT_URL="https://hc-ping.test/test-only-no-real-hc-id"
# ntfy — referenced via OnFailure handlers across the codebase.
# Secrets just need to satisfy the sops manifest check; ntfy itself is
# NOT enabled in the test VM (so no real notifications dialed). Adding
# a Phase 7 that wires a real ntfy server in-VM is on the roadmap;
# until then, these are stubs.
NTFY_CHANNEL="test-channel"
NTFY_PUB_TOKEN="tk_test_not_a_real_ntfy_token"
# OIDC test client — authelia REJECTS the config when
# identity_providers.oidc.clients is empty, so the test declares one
# OIDC route (`nori.lanRoutes.testapp.oidc`) which auto-generates two
# sops secrets per the networking module:
#   oidc-testapp-client-secret       raw secret, group=keys
#   oidc-testapp-client-secret-hash  PBKDF2 hash, owner=authelia-main
# Authelia uses its own variant of base64 in the pbkdf2 hash format,
# so generate it via authelia's own `crypto hash generate pbkdf2` tool
# — guaranteed parseable, deterministic per password.
TESTAPP_RAW="test-client-secret-not-a-real-secret"
TESTAPP_HASH="$(authelia crypto hash generate pbkdf2 --password "$TESTAPP_RAW" 2>/dev/null | sed -n 's/^Digest: //p')"

echo "==> generating RSA 2048 OIDC issuer key"
ISSUER_KEY="$(openssl genrsa 2048 2>/dev/null)"

echo "==> generating argon2id hash for test user"
# Authelia accepts the encoded `$argon2id$...` line directly. Use a
# deterministic salt so re-runs of this script produce a stable hash
# for the same password (helps PR reviewers diff the secrets file).
TEST_SALT="0123456789abcdef0123456789abcdef"
USER_HASH="$(printf 'test-password-do-not-use-in-prod' | argon2 "$TEST_SALT" -id -t 3 -m 16 -p 4 -e)"

USERS_YAML=$(cat <<EOF
users:
  nori:
    disabled: false
    displayname: "Test User"
    password: "$USER_HASH"
    email: nori@test.lan
    groups:
      - admin
EOF
)

# Build plaintext YAML via python for safe multiline-string escaping
# (RSA key + users yaml block).
PLAIN="$(mktemp)"
trap 'rm -f "$PLAIN"' EXIT

JWT="$JWT" SESSION="$SESSION" STORAGE="$STORAGE" HMAC="$HMAC" \
ISSUER_KEY="$ISSUER_KEY" USERS_YAML="$USERS_YAML" RESTIC_PASS="$RESTIC_PASS" \
CF_ACME_TOKEN="$CF_ACME_TOKEN" GATUS_ENV="$GATUS_ENV" \
RESTIC_SSH_KEY="$RESTIC_SSH_KEY" \
HEARTBEAT_URL="$HEARTBEAT_URL" \
NTFY_CHANNEL="$NTFY_CHANNEL" NTFY_PUB_TOKEN="$NTFY_PUB_TOKEN" \
TESTAPP_RAW="$TESTAPP_RAW" TESTAPP_HASH="$TESTAPP_HASH" \
python3 -c '
import os, sys, json
data = {
    "authelia-jwt-secret": os.environ["JWT"],
    "authelia-session-secret": os.environ["SESSION"],
    "authelia-storage-encryption-key": os.environ["STORAGE"],
    "authelia-oidc-hmac-secret": os.environ["HMAC"],
    "authelia-oidc-issuer-private-key": os.environ["ISSUER_KEY"],
    "authelia-users-database": os.environ["USERS_YAML"],
    "restic-password": os.environ["RESTIC_PASS"],
    "restic-ssh-key": os.environ["RESTIC_SSH_KEY"],
    "gatus-env": os.environ["GATUS_ENV"],
    "heartbeat-pi-url": os.environ["HEARTBEAT_URL"],
    "ntfy-channel": os.environ["NTFY_CHANNEL"],
    "ntfy-publisher-token": os.environ["NTFY_PUB_TOKEN"],
    "oidc-testapp-client-secret": os.environ["TESTAPP_RAW"],
    "oidc-testapp-client-secret-hash": os.environ["TESTAPP_HASH"],
    # Key intentionally uses underscore — caddy.nix references it as
    # `cloudflare_acme_token` via sops `key` field (the secret is named
    # `cloudflare-acme-token` with a hyphen). When the sopsFile is
    # overridden to point here, both shapes work via the `key` mapping.
    "cloudflare_acme_token": os.environ["CF_ACME_TOKEN"],
}
# json IS valid yaml — write that, sops handles it fine and we avoid
# yaml block-scalar indentation foot-guns.
json.dump(data, sys.stdout, indent=2)
print()
' > "$PLAIN"

echo "==> encrypting → $SECRETS_FILE"
# Explicit --config: sops discovery walks up from the input file and
# would find the root .sops.yaml first (its `secrets/.*\.yaml$` regex
# also matches `tests/secrets/test.yaml` — the regex isn't anchored).
# Force the test config to ensure the test key is the recipient.
cp "$PLAIN" "$SECRETS_FILE"
sops --config "$SOPS_CONFIG" --encrypt --in-place \
  --input-type json --output-type yaml "$SECRETS_FILE"

echo
echo "done."
echo "  test age key:  $KEY_FILE  (committed)"
echo "  test age pub:  $PUB_FILE   (committed)"
echo "  test secrets:  $SECRETS_FILE   (sops-encrypted, committed)"
