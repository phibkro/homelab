#!/usr/bin/env bash
#
# Doc-code coherence. Catches the specific drift class where a host
# (or other named module) is live in the repo, but a doc still calls
# it deferred / planned / not-yet-done.
#
# The rule: for each host actually declared under machines/, no markdown
# line in docs/ or at the repo root may mention both `machines/<host>/`
# AND a "deferred"-class word. If the host folder is present, it's live;
# saying otherwise in prose is stale.
#
# This is intentionally narrow — it requires the path reference, not
# just the bare host name — so the word "deferred" remains usable for
# legitimate non-host topics (email digest deferred, etc.).
#
# Invoked by flake.nix `checks.${system}.doc-coherence`. Run by hand:
#
#   bash scripts/checks/doc-coherence.sh .
#
# Exits 0 on success, 1 on any drift detected.

set -u
cd "${1:?usage: doc-coherence.sh <source-root>}"
fail=0

hosts=$(find machines -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
docs=$(find docs -name '*.md'; ls README.md 2>/dev/null)

for h in $hosts; do
  # Lines that mention machines/<host>/ AND a deferred-class
  # word, in either order. -i for case (DEFERRED is common).
  if grep -inE \
       "(machines/${h}[/ ].*\b(deferred|planned|pending|tbd)\b)|(\b(deferred|planned|pending|tbd)\b.*machines/${h}[/ ])" \
       $docs ; then
    echo
    echo "✗ host ${h} is live in machines/${h}/ but docs above"
    echo "  call it deferred/planned/pending. Either remove the"
    echo "  stale line or remove the host folder."
    fail=1
  fi
done

exit "$fail"
