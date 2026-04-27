#!/usr/bin/env bash
# Generate raw + PBKDF2 hash for a new lan-route OIDC client and
# print the two paste-ready sops lines. Designed to be piped to a
# remote bash -s via the `just oidc-key <name>` recipe; expects
# `openssl` and `authelia` on PATH (entered via `nix shell` by the
# caller).
#
# Output is sensitive — both values are secret material in different
# forms. Run from a terminal where you can paste into sops
# immediately and clear scrollback after.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <route-name>" >&2
    exit 1
fi

NAME="$1"

RAW=$(openssl rand -base64 32 | tr -d '=+/')
HASH=$(authelia crypto hash generate pbkdf2 \
    --variant sha512 \
    --iterations 310000 \
    --password "$RAW" \
    | grep '^Digest:' | cut -d' ' -f2)

cat <<EOF
# Paste these two lines into sops secrets/secrets.yaml under the
# top-level mapping. Single quotes keep YAML from interpreting \$.

oidc-${NAME}-client-secret: '${RAW}'
oidc-${NAME}-client-secret-hash: '${HASH}'
EOF
