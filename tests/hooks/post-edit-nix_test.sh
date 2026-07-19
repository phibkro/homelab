#!/usr/bin/env bash

set -euo pipefail

hook="${1:?usage: post-edit-nix_test.sh HOOK}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

repo="$scratch/repo"
fake_bin="$scratch/bin"
log="$scratch/nix.log"
mkdir -p "$repo/nested" "$fake_bin"
git -C "$repo" init -q
printf '{ }\n' >"$repo/default.nix"
printf '{ }\n' >"$repo/nested/module.nix"
printf '# docs\n' >"$repo/README.md"

printf '#!%s\n' "$BASH" >"$fake_bin/nix"
printf '%s\n' \
  'printf "%s" "$1" >>"$HOOK_TEST_LOG"' \
  'shift' \
  'printf "\\t%s" "$@" >>"$HOOK_TEST_LOG"' \
  'printf "\\n" >>"$HOOK_TEST_LOG"' \
  'if [[ "${HOOK_TEST_FAIL_FORMAT:-0}" == 1 && "$(head -n 1 "$HOOK_TEST_LOG")" == fmt* ]]; then exit 1; fi' \
  >>"$fake_bin/nix"
chmod +x "$fake_bin/nix"

for analyzer in statix deadnix; do
  printf '#!%s\n' "$BASH" >"$fake_bin/$analyzer"
  printf '%s\n' \
    'printf "%s" "$(basename "$0")" >>"$HOOK_TEST_LOG"' \
    'printf "\\t%s" "$@" >>"$HOOK_TEST_LOG"' \
    'printf "\\n" >>"$HOOK_TEST_LOG"' \
    >>"$fake_bin/$analyzer"
  chmod +x "$fake_bin/$analyzer"
done

export PATH="$fake_bin:$PATH"
export HOOK_TEST_LOG="$log"
export CLAUDE_PROJECT_DIR="$repo"

printf '{"tool_input":{"file_path":"%s/default.nix"}}' "$repo" | bash "$hook"

codex_patch="*** Begin Patch
*** Update File: README.md
*** Update File: nested/module.nix
*** Update File: nested/module.nix
*** Update File: ../outside.nix
*** End Patch"
HOOK_PATCH="$codex_patch" perl -MJSON::PP -e '
  print encode_json({ tool_input => { command => $ENV{HOOK_PATCH} } });
' | bash "$hook"

[[ "$(grep -c '^fmt' "$log")" == 2 ]]
grep -q $'^fmt\t--\tdefault.nix$' "$log"
grep -q $'^fmt\t--\tnested/module.nix$' "$log"
grep -q $'^statix\tcheck\tdefault.nix$' "$log"
grep -q $'^statix\tcheck\tnested/module.nix$' "$log"
grep -q $'^deadnix\t--fail\t--no-lambda-pattern-names\tdefault.nix$' "$log"
grep -q $'^deadnix\t--fail\t--no-lambda-pattern-names\tnested/module.nix$' "$log"
! grep -q 'README.md\|outside.nix' "$log"

before_size="$(stat -c %s "$log")"
printf '{"tool_input":{"file_path":"%s/README.md"}}' "$repo" | bash "$hook"
after_size="$(stat -c %s "$log")"
[[ "$before_size" == "$after_size" ]]

: >"$log"
export HOOK_TEST_FAIL_FORMAT=1
if printf '{"tool_input":{"file_path":"%s/default.nix"}}' "$repo" \
  | bash "$hook" 2>"$scratch/error"; then
  printf 'expected formatter failure\n' >&2
  exit 1
fi
grep -q 'project formatter failed' "$scratch/error"

printf 'ok — cross-provider Nix post-edit hook\n'
