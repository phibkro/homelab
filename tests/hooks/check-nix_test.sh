#!/usr/bin/env bash
# Exercise CLI dispatch without building VMs; classification comes from Nix eval.
set -euo pipefail
runner="$(realpath "${1:?usage: check-nix_test.sh RUNNER}")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
export CHECK_TEST_LOG="$scratch/build.log"
printf '#!%s\n' "$(command -v bash)" > "$scratch/bin/nix"
cat >> "$scratch/bin/nix" <<'STUB'
set -euo pipefail
if [[ "$*" == *builtins.currentSystem* ]]; then
  printf 'x86_64-linux'
elif [[ "$*" == *' eval '* ]]; then
  if [[ ${CHECK_TEST_EVAL_FAIL:-0} == 1 ]]; then exit 17; fi
  printf '{"e2e-static-contract":"fast","runtime-without-prefix":"vm","lint":"fast"}\n'
else
  printf '%s\n' "$@" > "$CHECK_TEST_LOG"
fi
STUB
chmod +x "$scratch/bin/nix"
export PATH="$scratch/bin:$PATH"
bash "$runner" fast
grep -Fx '.#checks.x86_64-linux.e2e-static-contract' "$CHECK_TEST_LOG"
grep -Fx '.#checks.x86_64-linux.lint' "$CHECK_TEST_LOG"
if grep -q runtime-without-prefix "$CHECK_TEST_LOG"; then echo 'Fast group built a VM' >&2; exit 1; fi
bash "$runner" vm runtime-without-prefix --impure
grep -Fx '.#checks.x86_64-linux.runtime-without-prefix' "$CHECK_TEST_LOG"
grep -Fx -- --impure "$CHECK_TEST_LOG"
grep -Fx -- --max-jobs "$CHECK_TEST_LOG"
bash "$runner" vm
for args in 'vm lint' 'vm absent' 'bogus' 'fast extra'; do
  rm -f "$CHECK_TEST_LOG"
  # Intentional split: each case is a CLI argument vector.
  # shellcheck disable=SC2086
  if bash "$runner" $args; then echo "Accepted invalid request: $args" >&2; exit 1; fi
  [[ ! -e "$CHECK_TEST_LOG" ]]
done
if CHECK_TEST_EVAL_FAIL=1 bash "$runner" fast; then echo 'Hidden evaluation failure' >&2; exit 1; fi
[[ ! -e "$CHECK_TEST_LOG" ]]
printf 'check-nix: metadata selects groups; invalid requests and evaluation failures never build\n'
