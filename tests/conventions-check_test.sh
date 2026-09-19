#!/usr/bin/env bash
set -euo pipefail

checker="$(realpath "${1:?conventions checker required}")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

check() {
  local expected=$1 repo=$2 actual=0
  bash "$checker" "$repo" >"$scratch/output" 2>&1 || actual=$?
  if [[ $actual != "$expected" ]]; then
    cat "$scratch/output" >&2
    printf 'expected exit %s, got %s for %s\n' "$expected" "$actual" "$repo" >&2
    exit 1
  fi
}

for lifecycle in idea spec spec-frozen build park archive; do
  repo="$scratch/$lifecycle"
  mkdir -p "$repo"
  printf 'Lifecycle: %s\n' "$lifecycle" >"$repo/STATE.md"
  touch "$repo/AGENTS.md"
  if [[ $lifecycle == idea ]]; then
    check 0 "$repo"
    continue
  fi

  check 1 "$repo"
  grep -Fq 'docs/specs/ required' "$scratch/output"
  mkdir "$repo/design-specs"
  check 1 "$repo"
  grep -Fq 'docs/specs/ required' "$scratch/output"
  mkdir -p "$repo/docs/specs"
  rmdir "$repo/design-specs"
  check 0 "$repo"
done

# Existing exception declarations keep their key, but must remain visible.
repo="$scratch/declared"
mkdir "$repo"
printf 'Lifecycle: build\n' >"$repo/STATE.md"
touch "$repo/AGENTS.md"
printf 'divergences:\n  - key: design-specs\n    reason: external contract\n' >"$repo/.conventions-exceptions"
check 0 "$repo"
grep -Fq 'DECLARED' "$scratch/output"
grep -Fq '[exception: design-specs]' "$scratch/output"

printf 'conventions-check: lifecycle, canonical path, legacy rejection, and declared exception passed\n'
