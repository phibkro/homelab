#!/usr/bin/env bash
#
# Routing table ↔ filesystem coherence. Catches three drift classes
# around the docs/ tree:
#
#   1. CLAUDE.md routes to a `docs/<path>.md` that doesn't exist
#      (would surface as a broken link to the next agent).
#   2. A `docs/reference/<file>.md` exists but CLAUDE.md doesn't
#      route to it (L2 reference is structurally session-aware;
#      every L2 doc must be discoverable via the routing table).
#   3. An L1 doc (`docs/{glossary,invariants,roadmap}.md`) is
#      missing from CLAUDE.md (mandatory-read; if not routed,
#      agents won't load them).
#
# Scoped to CLAUDE.md alone — the docs/README.md mirror lags by one
# commit sometimes and that's fine; the load-bearing surface is
# CLAUDE.md.
#
# Invoked by flake.nix `checks.${system}.routing-coherence`. Run by
# hand:
#
#   bash scripts/checks/routing-coherence.sh .
#
# Exits 0 on success, 1 on any incoherence detected.

set -u
cd "${1:?usage: routing-coherence.sh <source-root>}"
fail=0

# 1. Every `docs/<path>.md` referenced in CLAUDE.md must exist.
refs=$(grep -oE '`docs/[a-zA-Z0-9_/.-]+\.md`' CLAUDE.md | tr -d '`' | sort -u)
for r in $refs; do
  if [ ! -e "$r" ]; then
    echo "✗ CLAUDE.md routes to $r, but file does not exist"
    fail=1
  fi
done

# 2. Every docs/reference/*.md must be routed from CLAUDE.md.
for f in docs/reference/*.md; do
  if ! grep -qF "$f" CLAUDE.md; then
    echo "✗ $f exists but CLAUDE.md does not route to it"
    fail=1
  fi
done

# 3. L1 docs at docs/ root must be routed.
for f in docs/glossary.md docs/invariants.md docs/roadmap.md; do
  if [ ! -e "$f" ]; then
    echo "✗ L1 doc $f is missing (expected at docs/ root)"
    fail=1
  elif ! grep -qF "$f" CLAUDE.md; then
    echo "✗ L1 doc $f exists but CLAUDE.md does not route to it"
    fail=1
  fi
done

exit "$fail"
