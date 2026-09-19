#!/usr/bin/env bash
set -euo pipefail
planner="$(realpath "${1:?planner script required}")"
export HOMELAB_DEPLOYMENT_INDEX
index="$(realpath "${2:?generated deployment index required}")"
HOMELAB_DEPLOYMENT_INDEX="$index"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$scratch/repo" "$scratch/outside"
cd "$scratch/repo"
git init --quiet
git config user.name test
git config user.email test@example.invalid
mkdir -p \
  docs \
  infra/common/ansible/roles/base/tasks \
  services/bazarr \
  services/caddy/ansible \
  services/filmder \
  services/recyclarr/implementation
printf baseline > infra/common/ansible/roles/base/tasks/main.yml
printf baseline > services/bazarr/manifest.nix
printf baseline > services/filmder/nixos.nix
printf baseline > services/caddy/ansible/tasks.yml
printf baseline > services/recyclarr/implementation/radarr.yml
printf ignored > .gitignore
printf baseline > docs/old.md
git add .
git commit --quiet -m baseline
base="$(git rev-parse HEAD)"

plan() { bash "$planner" "$@" >"$scratch/plan.json" 2>"$scratch/stderr"; }
assert_plan() { jq -e "$@" "$scratch/plan.json" >/dev/null; }
reject() {
  if plan "$@"; then
    echo "unexpected planner success: $*" >&2
    exit 1
  fi
  test ! -s "$scratch/plan.json"
  test -s "$scratch/stderr"
}

reject --changed-since invalid-ref
reject --changed-since --all
(cd "$scratch/outside"; reject --changed-since HEAD)
reject --host unknown
reject --profile unknown
reject --workload unknown
printf null >"$scratch/bad.json"
(HOMELAB_DEPLOYMENT_INDEX="$scratch/bad.json"; reject --all)
cat "$index" "$index" >"$scratch/bad.json"
(HOMELAB_DEPLOYMENT_INDEX="$scratch/bad.json"; reject --all)
printf '{' >"$scratch/bad.json"
(HOMELAB_DEPLOYMENT_INDEX="$scratch/bad.json"; reject --all)
(HOMELAB_DEPLOYMENT_INDEX="$scratch/missing.json"; reject --all)

plan --changed-since HEAD
assert_plan '.hosts == [] and .untrackedFiles == []'
printf changed >> services/filmder/nixos.nix
# A malformed ownership value must propagate the downstream jq failure too.
jq '.sourceRoots["services/filmder"] = "invalid-host-array"' "$index" >"$scratch/bad.json"
(HOMELAB_DEPLOYMENT_INDEX="$scratch/bad.json"; reject --changed-since HEAD)
plan --changed-since HEAD
assert_plan '.hosts == ["workstation"] and .activationOrder == ["workstation"]'
git add .
plan --changed-since HEAD
assert_plan '.hosts == ["workstation"]'
git commit --quiet -m workstation
plan --changed-since "$base"
assert_plan '.hosts == ["workstation"]'
printf changed >> services/caddy/ansible/tasks.yml
plan --changed-since HEAD
assert_plan '.hosts == ["pi"] and .builds == [] and .plans == ["just pi::plan"] and .applies == ["just pi::deploy"] and .verifies == ["just pi::check"] and .activationOrder == ["pi"]'
git restore services/caddy/ansible/tasks.yml

# Coupled acquisition ownership covers manifests and implementation assets,
# while common Ansible mechanisms belong only to the Pi deployment backend.
printf changed >> services/bazarr/manifest.nix
plan --changed-since HEAD
assert_plan '.hosts == ["workstation"]'
git restore services/bazarr/manifest.nix
printf changed >> services/recyclarr/implementation/radarr.yml
plan --changed-since HEAD
assert_plan '.hosts == ["workstation"]'
git restore services/recyclarr/implementation/radarr.yml
printf changed >> infra/common/ansible/roles/base/tasks/main.yml
plan --changed-since HEAD
assert_plan '.hosts == ["pi"]'
git restore infra/common/ansible/roles/base/tasks/main.yml

# Git-backed flakes exclude untracked sources. Plan their owners but expose the
# paths verbatim and warn before the emitted build commands can be mistaken for coverage.
odd=$'services/caddy/ansible/new file\nwith newline.yml'
printf new >"$odd"
printf ignored >ignored
(cd services/caddy/ansible; plan --changed-since HEAD)
# jq variable, not shell interpolation.
# shellcheck disable=SC2016
assert_plan --arg odd "$odd" '.hosts == ["pi"] and .untrackedFiles == [$odd] and (.reasons | index("changed:" + $odd) != null)'
grep -q 'git add' "$scratch/stderr"
git add "$odd"
plan --changed-since HEAD
assert_plan '.hosts == ["pi"] and .untrackedFiles == []'
git commit --quiet -m pi

# Moves must invalidate both old and new owners even when Git detects a rename.
git mv services/filmder/nixos.nix services/caddy/ansible/moved.nix
plan --changed-since HEAD
assert_plan '.hosts == ["pi", "workstation"]'
git commit --quiet -m rename
plan --changed-since HEAD~1
assert_plan '.hosts == ["pi", "workstation"]'
rm services/caddy/ansible/moved.nix
plan --changed-since HEAD
assert_plan '.hosts == ["pi"]'
git restore services/caddy/ansible/moved.nix
printf docs >> docs/old.md
plan --changed-since HEAD
assert_plan '.hosts == [] and .reasons == ["docs-or-tests:docs/old.md"]'
git restore docs/old.md
printf new >unknown-source
plan --changed-since HEAD
assert_plan '.hosts == ["adelie", "pi", "workstation"] and .untrackedFiles == ["unknown-source"]'

plan --host workstation --workload jellyfin
assert_plan '.hosts == ["workstation"] and .activationOrder == ["workstation"]'
plan --host pi
assert_plan '.hosts == ["pi"] and .builds == [] and .applies == ["just pi::deploy"]'

# A corrupt real Git index must not be downgraded to an empty/successful plan.
printf broken >.git/index
reject --changed-since HEAD
printf 'deployment planner: Git boundary, selectors and filename cases passed\n'
