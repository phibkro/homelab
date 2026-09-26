#!/usr/bin/env bash
# Real Git index isolation; Nix is a recording boundary double, not a Nix test.
set -euo pipefail
hook="$(realpath "${1:?usage: pre-commit_test.sh HOOK}")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo" "$scratch/bin"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOOK_TEST_LOG="$scratch/checks.log"
printf '#!%s\n' "$(command -v bash)" > "$scratch/bin/nix"
cat >> "$scratch/bin/nix" <<'STUB'
set -euo pipefail
[[ "$PWD" != "$HOOK_TEST_REPO" ]]
[[ "$(cat partly-staged.nix)" == staged ]]
[[ "$(git show :partly-staged.nix)" == staged ]]
[[ ! -e untracked.txt ]]
[[ ! -e removed.txt ]]
[[ "$(cat ignored-but-tracked.txt)" == retained ]]
# Nix sees a clean Git source with a revision, holding exactly the staged content.
[[ "$(git show HEAD:partly-staged.nix)" == staged ]]
[[ -z "$(git status --porcelain --untracked-files=all)" ]]
printf '%s\n' "$*" >> "$HOOK_TEST_LOG"
exit "${HOOK_TEST_FAILURE:-0}"
STUB
chmod +x "$scratch/bin/nix"
export PATH="$scratch/bin:$PATH" HOOK_TEST_REPO="$scratch/repo"
cd "$scratch/repo"
git init -q
git config user.name fixture
git config user.email fixture@example.invalid
printf 'ignored-*\n' > .gitignore
printf 'retained\n' > ignored-but-tracked.txt
printf 'baseline\n' > partly-staged.nix
printf 'removed\n' > removed.txt
git add --force .
git commit --quiet -m baseline
printf 'staged\n' > partly-staged.nix
git add partly-staged.nix
git rm --quiet removed.txt
printf 'operator unstaged work\n' > partly-staged.nix
printf 'operator untracked work\n' > untracked.txt
# Exercise a real alternate index, as git commit may provide to hooks.
cp .git/index "$scratch/main-index-before"
cp .git/index "$scratch/alternate-index"
export GIT_INDEX_FILE="$scratch/alternate-index"
cp "$GIT_INDEX_FILE" "$scratch/index-before"
git diff --binary > "$scratch/work-before"
git diff --cached --binary > "$scratch/staged-before"
for failure in 0 19; do
  status=0
  HOOK_TEST_FAILURE="$failure" bash "$hook" || status=$?
  [[ "$status" == "$failure" ]]
  cmp "$GIT_INDEX_FILE" "$scratch/index-before"
  cmp .git/index "$scratch/main-index-before"
  git diff --binary > "$scratch/work-after"
  git diff --cached --binary > "$scratch/staged-after"
  cmp "$scratch/work-before" "$scratch/work-after"
  cmp "$scratch/staged-before" "$scratch/staged-after"
  [[ "$(cat untracked.txt)" == 'operator untracked work' ]]
done
[[ "$(wc -l < "$HOOK_TEST_LOG")" -eq 3 ]]
grep -Fx 'develop --command bash scripts/check-nix.sh fast' "$HOOK_TEST_LOG"
grep -Fx 'develop --command just pi::check' "$HOOK_TEST_LOG"
printf 'pre-commit: staged content validated; failure propagated; index and operator files preserved\n'
