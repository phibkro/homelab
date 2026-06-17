#!/usr/bin/env bash
# path-coherence — verify path-string references in code comments
# (and selected docs) resolve to existing files.
#
# This catches the drift class where a file moves or renames but a
# comment elsewhere still names the old path. Phase 1 of the
# modules-as-root restructure surfaced 10 such stale refs across
# the tree.
#
# Scope
#   in:  *.nix under repo root (excluding ./result*)
#        *.md under docs/reference/, docs/decisions/, docs/installs/
#        docs/glossary.md, docs/invariants.md, docs/README.md
#        .claude/skills/*/SKILL.md
#   out: docs/plans/ and docs/reports/ — time-accurate historical
#        narrative; intentionally describes past state
#
# Match modes
#   literal       modules/foo/bar.nix       → file must exist
#   placeholder   modules/foo/<X>.nix       → glob (<...> → *) must
#                                             match at least one file
#   skip          line contains
#                  "# path-coherence: skip" → line ignored
#
# Usage:
#   path-coherence.sh <repo-root>

set -u
root="${1:-.}"
cd "$root"

failfile=$(mktemp)
echo 0 > "$failfile"
trap 'rm -f "$failfile"' EXIT

# Path pattern: starts with modules/, machines/, or home/, ends in .nix.
# Allows placeholder syntax <X> mid-path. Stops at whitespace,
# parens, quotes, and other non-path characters.
regex='(modules|machines|home)/[a-zA-Z0-9/<>_.-]+\.nix'

# Files in scope
mapfile -t files < <(
  find . -name '*.nix' -not -path './result*' -not -path './.git/*' 2>/dev/null
  find docs/reference docs/decisions docs/installs -name '*.md' 2>/dev/null
  for f in docs/glossary.md docs/invariants.md docs/README.md; do
    [ -f "$f" ] && echo "$f"
  done
  find .claude/skills -name 'SKILL.md' 2>/dev/null
)

for f in "${files[@]}"; do
  [ -f "$f" ] || continue

  # Each (line, content) pair
  while IFS=: read -r lineno content; do
    # Skip annotated lines
    if echo "$content" | grep -q "path-coherence: skip"; then
      continue
    fi

    # Extract each unique path reference on this line
    while IFS= read -r path; do
      [ -z "$path" ] && continue

      if [[ "$path" == *"<"*">"* ]]; then
        # Placeholder mode: <...> → *, then bash glob
        glob=$(echo "$path" | sed 's/<[^>]*>/*/g')
        shopt -s nullglob
        matches=($glob)
        shopt -u nullglob
        if [ ${#matches[@]} -eq 0 ]; then
          echo "✗ $f:$lineno: placeholder '$path' matches no files (glob '$glob')"
          echo 1 > "$failfile"
        fi
      else
        # Literal mode
        if [ ! -e "$path" ]; then
          echo "✗ $f:$lineno: dead reference '$path'"
          echo 1 > "$failfile"
        fi
      fi
    done < <(echo "$content" | grep -oE "$regex" | sort -u)
  done < <(grep -nE "$regex" "$f" 2>/dev/null)
done

fail=$(cat "$failfile")

if [ "$fail" = "0" ]; then
  echo "✓ all path references resolve"
  exit 0
fi

echo
echo "Path-coherence: dead references found."
echo
echo "Either:"
echo "  - fix the path (the file moved/renamed)"
echo "  - annotate the line with '# path-coherence: skip' if the"
echo "    reference is intentionally historical (describes a"
echo "    previous state) or otherwise decoupled from filesystem"
exit 1
