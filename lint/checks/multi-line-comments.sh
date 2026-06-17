#!/usr/bin/env bash
# multi-line-comments — flag 3+ consecutive `# ` lines as a lint
# violation per the documentation-writing.md convention.
#
# Multi-line `#` blocks are ambiguous: they could be documentation
# (extractable into generated docs) or narrative (rationale for
# maintainers). The author MUST choose:
#
#   /** ... */    documentation — extracted by nixdoc into generated
#                 docs. For "how to USE this code."
#
#   /* ... */     narrative — Nix-valid multi-line comment, NOT
#                 extracted. For "why this code is shaped this way."
#
#   # multi-line: ok    explicit opt-out for blocks that are
#                       genuinely intended as inline `#` despite
#                       being 3+ lines (rare; e.g. ASCII tables
#                       that need uniform leading `#`).
#
# Scope: .nix files under repo (excluding ./result*).
#
# Output: one violation per detected block:
#   <file>:<start>-<end> N consecutive # lines
#
# The Stage 4 convention enforcement; see
# docs/reference/documentation-writing.md.

set -u
root="${1:-.}"
cd "$root"

failfile=$(mktemp)
echo 0 > "$failfile"
trap 'rm -f "$failfile"' EXIT

violations=0

while IFS= read -r f; do
  [ -f "$f" ] || continue
  # awk reports each block start-end-count; skip shebangs; skip
  # blocks that contain "multi-line: ok" anywhere.
  awk -v file="$f" '
    BEGIN { in_block = 0; start = 0; count = 0; has_optout = 0 }
    /^[[:space:]]*#!/ { flush(); next }
    /^[[:space:]]*#/ {
      if (!in_block) { start = NR; count = 0; has_optout = 0; in_block = 1 }
      count++
      if (index($0, "multi-line: ok") > 0) has_optout = 1
      next
    }
    { flush() }
    END { flush() }
    function flush() {
      if (in_block && count >= 3 && !has_optout) {
        print file ":" start "-" (start + count - 1) " " count " consecutive # lines"
      }
      in_block = 0; count = 0; has_optout = 0
    }
  ' "$f"
done < <(find . -name '*.nix' -not -path './result*' -not -path './.git/*' 2>/dev/null | sort) > /tmp/mlc-violations.$$

count=$(wc -l < /tmp/mlc-violations.$$)
if [ "$count" -gt 0 ]; then
  cat /tmp/mlc-violations.$$
  echo
  echo "✗ $count multi-line # blocks found."
  echo
  echo "Each 3+ consecutive # block must be one of:"
  echo "  /** ... */   doc-comment (extracted to generated docs)"
  echo "  /* ... */    narrative (Nix-valid multi-line, not extracted)"
  echo "  # multi-line: ok    explicit opt-out (annotate the block)"
  echo
  echo "See docs/reference/documentation-writing.md § the convention."
  rm /tmp/mlc-violations.$$
  exit 1
fi
rm /tmp/mlc-violations.$$
echo "✓ no multi-line # blocks"
