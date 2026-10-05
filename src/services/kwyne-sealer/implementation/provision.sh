#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
stage=configuration
work=
cleanup() {
  status=$?
  if [[ -n "$work" ]] && ! rm -rf -- "$work"; then
    printf 'SealerProvisioningCleanupFailure directory=%s\n' "$work" >&2
  fi
  if (( status != 0 )); then printf 'SealerProvisioningFailure stage=%s exit=%s\n' "$stage" "$status" >&2; fi
}
trap cleanup EXIT
: "${KWYNE_SOURCE_REVISION:?}" "${KWYNE_SOURCE_REMOTE:?}" "${KWYNE_SOURCE_DIRECTORY:?}" "${CREDENTIALS_DIRECTORY:?}"
[[ "$KWYNE_SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]]
mkdir -p "$KWYNE_SOURCE_DIRECTORY"
output="$KWYNE_SOURCE_DIRECTORY/$KWYNE_SOURCE_REVISION"
# Never overwrite a published bundle, including after a credentials rotation.
if [[ -s "$output/sealer.js" && -s "$output/sha256" ]]; then
  (cd "$output" && sha256sum --check --status sha256)
  exit 0
fi
work=$(mktemp -d "$KWYNE_SOURCE_DIRECTORY/.provision.XXXXXXXX")
stage=authority-fetch
git init --quiet "$work/checkout"
auth=$(printf '%s:%s' "$KWYNE_SOURCE_USERNAME" "$(cat "$CREDENTIALS_DIRECTORY/authority-token")" | base64 -w0)
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: Basic $auth" \
  git -C "$work/checkout" fetch --quiet --no-tags "$KWYNE_SOURCE_REMOTE" '+refs/heads/main:refs/remotes/authority/main'
unset auth
stage=sealed-revision
git -C "$work/checkout" merge-base --is-ancestor "$KWYNE_SOURCE_REVISION" refs/remotes/authority/main
git -C "$work/checkout" checkout --quiet --detach "$KWYNE_SOURCE_REVISION"
cd "$work/checkout"
stage=runtime-version
[[ "$(jq -r .packageManager package.json)" == "bun@$(bun --version)" ]]
stage=frozen-dependencies
# No lifecycle hooks run as root; a registry/lock error never gets an unfrozen fallback.
bun install --frozen-lockfile --ignore-scripts
stage=bundle
mkdir "$work/published"
bun build src/sealer/main.ts --target=bun --outfile="$work/published/sealer.js"
(cd "$work/published" && sha256sum sealer.js > sha256)
chmod 0444 "$work/published/"*
stage=publish
mv "$work/published" "$output"
chmod 0555 "$output"
printf 'Sealer source ready revision=%s\n' "$KWYNE_SOURCE_REVISION"
