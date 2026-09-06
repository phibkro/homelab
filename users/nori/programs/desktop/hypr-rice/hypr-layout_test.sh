#!/usr/bin/env bash
set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
capture=$tmp/capture

{
  printf '#!%s\n' "$BASH"
  printf '%s\n' 'printf '\''%s\0'\'' "$@" > "$HYPR_LAYOUT_CAPTURE"'
  printf '%s\n' 'printf '\''%s\n'\'' "${HYPR_LAYOUT_RESPONSE:-ok}"'
} > "$tmp/hyprctl"
chmod +x "$tmp/hyprctl"

run() {
  HYPRCTL_BIN="$tmp/hyprctl" HYPR_LAYOUT_CAPTURE="$capture" bash "$script" "$@"
}

expect_eval() {
  local expected=$1
  mapfile -d '' -t args < "$capture"
  [[ ${#args[@]} -eq 3 ]]
  [[ ${args[0]} == -r ]]
  [[ ${args[1]} == eval ]]
  [[ ${args[2]} == "$expected" ]]
}

run 'a b; a d; c c'
expect_eval '_G.hypr_rice_apply_hex("6170706c79", "6120623b206120643b20632063", "", "")'

run --columns '1 2' --rows 'repeat(1,3)' 'a b; a d; c c'
expect_eval '_G.hypr_rice_apply_hex("6170706c79", "6120623b206120643b20632063", "312032", "72657065617428312c3329")'

run reset
expect_eval '_G.hypr_rice_apply_hex("7265736574", "", "", "")'

if run --columns >/dev/null 2>&1; then exit 1; fi
if run --rows a --rows b 'a;b' >/dev/null 2>&1; then exit 1; fi
if run --unknown value >/dev/null 2>&1; then exit 1; fi
if run reset extra >/dev/null 2>&1; then exit 1; fi
if run '1 1' extra >/dev/null 2>&1; then exit 1; fi

run -- '-custom'
expect_eval '_G.hypr_rice_apply_hex("6170706c79", "2d637573746f6d", "", "")'

raw='x"); error("boom'
run "$raw"
mapfile -d '' -t args < "$capture"
[[ ${args[2]} != *boom* ]]
[[ ${args[2]} == '_G.hypr_rice_apply_hex("6170706c79", "7822293b206572726f722822626f6f6d", "", "")' ]]

if HYPR_LAYOUT_RESPONSE='error: hypr-rice: invalid area name' run 'bad input' >"$tmp/error" 2>&1; then
  printf '%s\n' 'hypr-layout accepted a Hyprland eval error' >&2
  exit 1
fi
grep -qxF 'error: hypr-rice: invalid area name' "$tmp/error"

printf '%s\n' 'hypr-layout transport tests passed'
