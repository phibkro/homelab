#!/usr/bin/env bash
set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
calls=$tmp/calls
queue=$tmp/queue
export RICE_PALETTE_CATEGORIES='Layout Space Window System Session Help Utility Testing'

printf '#!%s\n' "$BASH" >"$tmp/fuzzel"
cat >>"$tmp/fuzzel" <<'EOF'
set -euo pipefail
{
  printf 'xdg=%s\n' "${XDG_DATA_DIRS-<unset>}"
  printf 'set=%s\n' "${RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS_SET-<unset>}"
  printf 'original=%s\n' "${RICE_PALETTE_ORIGINAL_XDG_DATA_DIRS-<unset>}"
  printf 'args='
  printf '%s|' "$@"
  printf '\n--\n'
} >>"$RICE_PALETTE_CALLS"
if [[ -s $RICE_PALETTE_QUEUE ]]; then
  IFS='|' read -r status output <"$RICE_PALETTE_QUEUE"
  printf '%s' "$output"
  exit "$status"
fi
EOF
chmod +x "$tmp/fuzzel"

run() {
  local unset_xdg=0
  if [[ ${1-} == --unset-xdg ]]; then
    unset_xdg=1
    shift
  fi
  : >"$calls"
  : >"$queue"
  local -a command=(env)
  [[ $unset_xdg -eq 0 ]] || command+=(-u XDG_DATA_DIRS)
  command+=(
    RICE_PALETTE_CALLS="$calls"
    RICE_PALETTE_QUEUE="$queue"
    FUZZEL_BIN="$tmp/fuzzel"
    RICE_PRIVATE_DATA_DIR=/private/share
    RICE_LAUNCH_PREFIX_BIN=/nix/store/fake/bin/rice-launch
    RICE_PALETTE_SELF="$script"
  )
  command+=("$@")
  "${command[@]}"
}

run XDG_DATA_DIRS=/existing bash "$script"
grep -Fxq 'xdg=/private/share:/existing' "$calls"
grep -Fxq 'set=1' "$calls"
grep -Fxq 'original=/existing' "$calls"
grep -Fq -- '--fields=filename,name,generic,keywords|' "$calls"
grep -Fq -- '--launch-prefix|/nix/store/fake/bin/rice-launch|' "$calls"

run --unset-xdg bash "$script"
grep -Fxq 'xdg=/private/share:/usr/local/share:/usr/share' "$calls"
grep -Fxq 'set=0' "$calls"

run XDG_DATA_DIRS=/existing bash "$script" alphabetical
grep -Fq -- '--no-sort|--match-workers=0|' "$calls"

run XDG_DATA_DIRS=/existing bash "$script" category Window
grep -Fq -- '--search|Window:|' "$calls"

run XDG_DATA_DIRS=/existing bash "$script" category Testing
grep -Fq -- '--search|Testing:|' "$calls"

: >"$calls"
printf '0|Layout\n' >"$queue"
XDG_DATA_DIRS=/existing \
RICE_PALETTE_CALLS="$calls" \
RICE_PALETTE_QUEUE="$queue" \
FUZZEL_BIN="$tmp/fuzzel" \
RICE_PRIVATE_DATA_DIR=/private/share \
RICE_LAUNCH_PREFIX_BIN=/nix/store/fake/bin/rice-launch \
RICE_PALETTE_SELF="$script" \
  bash "$script" categories
grep -Fq -- '--only-match|' "$calls"
grep -Fq -- '--search|Layout:|' "$calls"
[[ $(grep -c '^xdg=/private/share:/existing$' "$calls") -eq 2 ]]

: >"$calls"
printf '1|\n' >"$queue"
XDG_DATA_DIRS=/existing \
RICE_PALETTE_CALLS="$calls" \
RICE_PALETTE_QUEUE="$queue" \
FUZZEL_BIN="$tmp/fuzzel" \
RICE_PRIVATE_DATA_DIR=/private/share \
RICE_LAUNCH_PREFIX_BIN=/nix/store/fake/bin/rice-launch \
RICE_PALETTE_SELF="$script" \
  bash "$script" categories
[[ $(grep -c '^xdg=' "$calls") -eq 1 ]]

if run XDG_DATA_DIRS=/existing bash "$script" unknown 2>/dev/null; then
  echo 'rice-palette accepted an unknown view' >&2
  exit 1
fi

echo 'rice-palette behavior tests passed'
