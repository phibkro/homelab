#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: hypr-layout [--columns EXPR] [--rows EXPR] LAYOUT' '       hypr-layout reset' >&2
  exit 2
}

hex() {
  printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'
}

columns=
rows=
seen_columns=false
seen_rows=false

if [[ ${1-} == reset ]]; then
  [[ $# -eq 1 ]] || usage
  action=reset
  expression=
elif [[ $# -gt 0 ]]; then
  action=apply
  while [[ $# -gt 0 ]]; do
    case $1 in
      --columns)
        [[ $seen_columns == false && $# -ge 2 ]] || usage
        seen_columns=true
        columns=$2
        shift 2
        ;;
      --rows)
        [[ $seen_rows == false && $# -ge 2 ]] || usage
        seen_rows=true
        rows=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  [[ $# -eq 1 ]] || usage
  expression=$1
else
  usage
fi

hyprctl_bin=${HYPRCTL_BIN:-}
if [[ -z $hyprctl_bin ]]; then
  hyprctl_bin=$(command -v hyprctl || true)
fi
if [[ -z $hyprctl_bin || ! -x $hyprctl_bin ]]; then
  printf '%s\n' 'hypr-layout: hyprctl is not available in PATH' >&2
  exit 127
fi

call="_G.hypr_rice_apply_hex(\"$(hex "$action")\", \"$(hex "$expression")\", \"$(hex "$columns")\", \"$(hex "$rows")\")"
if ! output=$("$hyprctl_bin" -r eval "$call" 2>&1); then
  printf '%s\n' "$output" >&2
  exit 1
fi
if [[ $output == error:* ]]; then
  printf '%s\n' "$output" >&2
  exit 1
fi
printf '%s\n' "$output"
