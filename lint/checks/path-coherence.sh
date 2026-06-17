#!/usr/bin/env bash
# path-coherence — verify path-string references in code, comments,
# and selected docs resolve to existing files.
#
# Catches the drift class where a file moves or renames but a
# reference elsewhere still names the old path. Phase 1 of the
# modules-as-root restructure surfaced 10 such stale refs across
# the tree; Phase 4 surfaced 4 more.
#
# Two reference shapes are validated:
#
#   absolute-from-repo-root      modules/foo/bar.nix
#                                → checked against repo-root
#
#   relative-from-file           ../../home/core.nix
#                                ./sibling.nix
#                                → resolved against dirname($file),
#                                  then checked
#
# Both shapes catch real drift: absolute paths in comments/docs go
# stale on rename; relative imports in Nix code go stale when either
# the importer or the import target moves and the depth no longer
# matches. The Phase 4 modules-as-root move was lucky — every
# `../../home/X` import in `machines/<host>/home.nix` preserved its
# resolution because both trees moved by equal depth. A future move
# that breaks the depth-equality won't have that luck; this check
# catches it before eval.
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
#   literal       modules/foo/bar.nix   → file must exist
#   placeholder   modules/foo/<X>.nix   → glob (<...> → *) must
#                                         match at least one file
#   relative      ../../home/core.nix   → resolved against dirname,
#                                         then literal check
#
# Skip annotations
#   line-level    line contains
#                   "path-coherence: skip" → that line ignored
#   file-level    file contains anywhere
#                   "path-coherence: skip-file" → whole file ignored
#                   Use at top of skill/tutorial files where every
#                   path-shaped reference is illustrative.
#   block-level   line containing "path-coherence: skip-block" opens
#                 a skip range; line containing "path-coherence: end-skip"
#                 closes it. All lines BETWEEN (inclusive) are skipped.
#                 Use for fenced code blocks in markdown where HTML
#                 comments would render as literal code.
#
# Embed annotations as HTML comments in markdown:
#   <!-- path-coherence: skip-file — illustrative tutorial -->
#   <!-- path-coherence: skip-block — fenced example -->
#   <!-- path-coherence: end-skip -->
#
# Usage:
#   path-coherence.sh <repo-root>

set -u
root="${1:-.}"
cd "$root"

failfile=$(mktemp)
echo 0 > "$failfile"
trap 'rm -f "$failfile"' EXIT

# Absolute-from-root: starts with modules/, machines/, or home/, ends
# in .nix. Allows placeholder syntax <X> mid-path. The leading-char
# guard (handled per-match below) keeps this from matching the suffix
# of a relative path.
regex_abs='(modules|machines|home)/[a-zA-Z0-9/<>_.-]+\.nix'

# Relative-from-file: one or more `./` or `../` segments followed by
# a path ending in .nix. Captures the FULL relative form for resolution
# against the importing file's directory.
regex_rel='(\.\.?/)+[a-zA-Z0-9/<>_.-]+\.nix'

# Files in scope. Widened post-review (2026-06-17 PR review) to catch
# drift in session-start mandatory reading (roadmap, runbooks) + the
# top-level README and secrets/README — the files agents and operators
# actually read first. Previously these were silently excluded; bulk-
# moves left stale refs in exactly the docs humans look at.
mapfile -t files < <(
  find . -name '*.nix' -not -path './result*' -not -path './.git/*' 2>/dev/null
  find docs/reference docs/decisions docs/installs docs/runbooks -name '*.md' 2>/dev/null
  for f in docs/glossary.md docs/invariants.md docs/README.md docs/roadmap.md README.md secrets/README.md; do
    [ -f "$f" ] && echo "$f"
  done
  find .claude/skills -name 'SKILL.md' 2>/dev/null
)

check_literal() {
  local f=$1 lineno=$2 path=$3 label=$4
  if [[ "$path" == *"<"*">"* ]]; then
    local glob
    glob=$(echo "$path" | sed 's/<[^>]*>/*/g')
    shopt -s nullglob
    local matches=($glob)
    shopt -u nullglob
    if [ ${#matches[@]} -eq 0 ]; then
      echo "✗ $f:$lineno: placeholder '$path' matches no files (glob '$glob')"
      echo 1 > "$failfile"
    fi
  else
    if [ ! -e "$path" ]; then
      echo "✗ $f:$lineno: dead $label '$path'"
      echo 1 > "$failfile"
    fi
  fi
}

for f in "${files[@]}"; do
  [ -f "$f" ] || continue

  # File-level skip: any occurrence of "path-coherence: skip-file"
  # in the file skips it wholesale. The skip marker MUST be paired
  # with a rationale (after `—` on the same line). Used for
  # tutorial/skill files where every path-shaped reference is
  # illustrative shape, not a real file ref.
  if grep -q "path-coherence: skip-file" "$f"; then
    continue
  fi

  dir=$(dirname "$f")

  # Compute block-skip line ranges: every line BETWEEN a "skip-block"
  # opener and the matching "end-skip" closer (inclusive on both sides)
  # is ignored. Multiple non-nested ranges per file allowed.
  block_skip_lines=$(awk '
    /path-coherence: skip-block/ { in_block = 1; bs = NR; next }
    /path-coherence: end-skip/   {
      if (in_block) { for (i = bs; i <= NR; i++) print i; in_block = 0 }
      next
    }
    END { if (in_block) for (i = bs; i <= NR; i++) print i
    }
  ' "$f")

  while IFS=: read -r lineno content; do
    # Line-level skip
    if echo "$content" | grep -q "path-coherence: skip"; then
      continue
    fi
    # Block-level skip
    if [ -n "$block_skip_lines" ] && echo "$block_skip_lines" | grep -qE "^${lineno}\$"; then
      continue
    fi

    # Absolute refs (repo-root paths in comments/docs/code-strings)
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      # If this token appears immediately after `./` or `../`, it's
      # actually the tail of a relative path; the relative pass handles it.
      escaped="${path//./\\.}"
      if echo "$content" | grep -qE "(\.\.?/)+${escaped}"; then
        continue
      fi
      check_literal "$f" "$lineno" "$path" "reference"
    done < <(echo "$content" | grep -oE "$regex_abs" | sort -u)

    # Relative refs are validated in EVERY scoped file (.nix, .md,
    # SKILL.md). Illustrative refs in prose (an import shape quoted
    # as code-style, a tutorial path the reader is meant to create)
    # use the same line-level `path-coherence: skip` annotation as
    # absolute refs. In markdown, embed the annotation as an HTML
    # comment so it disappears on render:
    #   `../../home/core.nix` <!-- path-coherence: skip — illustrative -->
    while IFS= read -r relpath; do
      [ -z "$relpath" ] && continue
      resolved=$(realpath -m --relative-to=. "$dir/$relpath" 2>/dev/null)
      [ -z "$resolved" ] && continue
      check_literal "$f" "$lineno" "$resolved" "relative ref ($relpath)"
    done < <(echo "$content" | grep -oE "$regex_rel" | sort -u)
  done < <(grep -nE "${regex_abs}|${regex_rel}" "$f" 2>/dev/null)
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
