#!/usr/bin/env bash
# Check classification is declared on the derivations in checks/e2e.nix.
set -euo pipefail
mode="${1:?usage: check-nix.sh fast|vm [VM_NAME] [--impure]}"
shift
name=""
if [[ "$mode" == vm && $# -gt 0 && $1 != --* ]]; then name="$1"; shift; fi
case "$mode" in fast|vm) ;; *) echo "Unknown check group: $mode" >&2; exit 2;; esac
nix_args=(--extra-experimental-features 'nix-command flakes')
eval_args=()
if [[ ${1:-} == --impure ]]; then eval_args=(--impure); shift; fi
[[ $# == 0 ]] || { echo 'Unexpected check arguments' >&2; exit 2; }
system="$(nix "${nix_args[@]}" eval --impure --raw --expr builtins.currentSystem)"
checks="$(nix "${nix_args[@]}" eval "${eval_args[@]}" --json ".#checks.$system" --apply '
  checks: builtins.mapAttrs (_: check: check.homelabCheckGroup or "fast") checks
')"
selected="$(jq -er --arg group "$mode" '[to_entries[] | select(.value == $group) | .key] | if length == 0 then error("Empty check group") else .[] end' <<<"$checks")"
if [[ -n "$name" ]]; then
  jq -e --arg name "$name" --arg group "$mode" '.[$name] == $group' <<<"$checks" >/dev/null || {
    printf 'Unknown %s check: %s\nAvailable:\n%s\n' "$mode" "$name" "$selected" >&2; exit 2;
  }
  selected="$name"
fi
installables=()
while IFS= read -r check; do installables+=(".#checks.$system.$check"); done <<<"$selected"
printf 'Running %s Nix checks (%d):\n%s\n' "$mode" "${#installables[@]}" "$selected" >&2
build_args=()
# A group may contain several VMs; admit only one heavy Nix job at a time.
if [[ "$mode" == vm ]]; then build_args=(--max-jobs 1); fi
exec nix "${nix_args[@]}" build "${eval_args[@]}" "${build_args[@]}" --no-link --print-build-logs "${installables[@]}"
