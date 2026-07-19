#!/usr/bin/env bash

# Shared Claude Code / Codex PostToolUse hook for Nix edits.
#
# Claude Edit/Write calls provide tool_input.file_path. Codex apply_patch calls
# provide the patch in tool_input.command and match the Edit|Write aliases. The
# hook normalizes both forms, rejects paths outside the repository, formats only
# existing *.nix files, then reports targeted statix/deadnix findings.

set -uo pipefail

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
root="$(realpath -m -- "$root")"

if ! command -v perl >/dev/null 2>&1; then
  printf 'post-edit-nix: perl is required to parse hook input safely\n' >&2
  exit 2
fi

mapfile -d '' -t candidates < <(
  printf '%s' "$input" | perl -MJSON::PP -0777 -e '
    my $document = eval { decode_json(<STDIN>) } // {};
    my $tool_input = ref($document->{tool_input}) eq "HASH"
      ? $document->{tool_input}
      : {};
    my @paths;

    push @paths, $tool_input->{file_path}
      if defined $tool_input->{file_path};

    my $command = $tool_input->{command} // "";
    while ($command =~ /^\*\*\* (?:Add|Update) File: (.+)$/mg) {
      push @paths, $1;
    }
    while ($command =~ /^\*\*\* Move to: (.+)$/mg) {
      push @paths, $1;
    }

    print "$_\0" for @paths;
  '
)

declare -a files=()
declare -A seen=()

for candidate in "${candidates[@]}"; do
  [[ "$candidate" == *.nix ]] || continue

  if [[ "$candidate" == /* ]]; then
    absolute="$(realpath -m -- "$candidate")"
  else
    absolute="$(realpath -m -- "$root/$candidate")"
  fi

  case "$absolute" in
    "$root"/*) ;;
    *) continue ;;
  esac

  [[ -f "$absolute" ]] || continue
  relative="${absolute#"$root"/}"
  if [[ -z "${seen[$relative]:-}" ]]; then
    files+=("$relative")
    seen["$relative"]=1
  fi
done

[[ "${#files[@]}" -gt 0 ]] || exit 0

if ! format_output="$(cd "$root" && nix fmt -- "${files[@]}" 2>&1)"; then
  printf 'post-edit-nix: project formatter failed for %s\n%s\n' \
    "${files[*]}" "$format_output" >&2
  exit 2
fi

analysis_output=""
analysis_status=0
if command -v statix >/dev/null 2>&1 && command -v deadnix >/dev/null 2>&1; then
  analysis_output="$({
    cd "$root" || exit 1
    statix check "${files[@]}" || analysis_status=1
    deadnix --fail --no-lambda-pattern-names "${files[@]}" || analysis_status=1
    exit "$analysis_status"
  } 2>&1)"
  analysis_status=$?
fi

if [[ "$analysis_status" -ne 0 ]]; then
  message="$(printf '%s\n' "$analysis_output" | tail -n 40)"
  printf '%s' "$message" | perl -MJSON::PP -0777 -e '
    my $message = <STDIN>;
    print encode_json({
      hookSpecificOutput => {
        hookEventName => "PostToolUse",
        additionalContext => "Nix post-edit diagnostics found issues:\n$message",
      },
    });
  '
fi

exit 0
