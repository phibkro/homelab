#!/usr/bin/env bash
# Verify the shared entry point, scoped guides and documentation map agree.
set -euo pipefail
cd "${1:?usage: routing-coherence.sh <source-root> [inventory-json]}"
fail=0

for guide in AGENTS.md CLAUDE.md src/infra/AGENTS.md src/infra/pi/AGENTS.md src/services/AGENTS.md src/users/AGENTS.md docs/README.md; do
  if [[ ! -f "$guide" ]]; then
    echo "Missing agent route: $guide" >&2
    fail=1
    continue
  fi
  # Local Markdown links only; anchors and web URLs are not filesystem paths.
  while IFS= read -r target; do
    target=${target%%#*}
    [[ -z "$target" || "$target" == *://* ]] && continue
    if [[ ! -e "$(dirname "$guide")/$target" ]]; then
      echo "$guide routes to missing path: $target" >&2
      fail=1
    fi
  done < <(grep -oE '\]\([^ )]+\)' "$guide" | sed -E 's/^\]\(//; s/\)$//' || true)
done

for route in 'AGENTS.md' 'docs/README.md' 'src/infra/AGENTS.md' 'src/services/AGENTS.md' 'src/users/AGENTS.md'; do
  owner=AGENTS.md
  [[ "$route" == AGENTS.md ]] && owner=CLAUDE.md
  if ! grep -qF "($route)" "$owner"; then
    echo "$owner must link to $route" >&2
    fail=1
  fi
done
for doc in docs/reference/*.md docs/glossary.md docs/invariants.md docs/roadmap.md; do
  if [[ ! -f "$doc" ]] || ! grep -qF "(${doc#docs/})" docs/README.md; then
    echo "Documentation map must link to existing $doc" >&2
    fail=1
  fi
done

# Exercise the onboarding query against generated facts, never a copied answer key.
if [[ $# -ge 2 ]]; then
  query=$(sed -n '/<!-- onboarding-query:start -->/,/<!-- onboarding-query:end -->/p' \
    docs/installs/agent-onboarding-test.md | sed '1d; 2d; $d; /^```$/d')
  [[ -n "$query" ]] || { echo "Missing onboarding query" >&2; exit 1; }
  jq -e "$query" "$2" | jq -e '
    (.hosts | length > 0) and (.jellyfin | type == "object")
    and (.backup.enabled | type == "boolean")
    and (.deployment.targets | type == "object")' >/dev/null
fi
exit "$fail"
