#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
cd "$repo"
work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf -- "$work"' EXIT
mkdir "$work/credentials"
sops -d --extract '["gitlab-kwyne-sealer-token"]' secrets/workstation-runtime.yaml > "$work/credentials/authority-token"
export CREDENTIALS_DIRECTORY="$work/credentials"
export KWYNE_SOURCE_DIRECTORY="$work/source"
export KWYNE_SOURCE_REVISION
KWYNE_SOURCE_REVISION=$(jq -r .revision src/services/kwyne-sealer/deployment.json)
export KWYNE_SOURCE_REMOTE
KWYNE_SOURCE_REMOTE=$(jq -r .repos.kwyne.remote src/services/kwyne-sealer/deployment.json)
export KWYNE_SOURCE_USERNAME
KWYNE_SOURCE_USERNAME=$(jq -r .authority.username src/services/kwyne-sealer/deployment.json)
bash src/services/kwyne-sealer/implementation/provision.sh
# The production credential never enters a VM derivation or Nix store.
rm -- "$work/credentials/authority-token"
unset CREDENTIALS_DIRECTORY
nix-build --impure src/services/kwyne-sealer/tests/default.nix \
  --argstr bundle "$work/source/$KWYNE_SOURCE_REVISION/sealer.js" \
  --no-out-link -j 1 --cores 2
