#!/usr/bin/env bash
set -euo pipefail

: "${HOMELAB_DEPLOYMENT_INDEX:?HOMELAB_DEPLOYMENT_INDEX must point to the generated deployment index}"

usage() {
  cat <<'EOF'
usage: deployment-plan [selectors]

Selectors may be repeated and are unioned:
  --changed-since REF   derive targets from committed, working-tree and untracked changes
  --host NAME           include one inventory target
  --profile NAME        include every target selecting the profile
  --workload NAME       include every target placing the workload
  --all                 include every target
EOF
}

selected='[]'
reason='[]'

add_hosts() {
  local hosts_json="$1" why="$2"
  selected="$(jq -cn --argjson left "$selected" --argjson right "$hosts_json" '$left + $right | unique')"
  reason="$(jq -cn --argjson current "$reason" --arg why "$why" '$current + [$why]')"
}

lookup() {
  local section="$1" name="$2"
  jq -ce --arg section "$section" --arg name "$name" '.[$section][$name] // error("unknown " + $section + " selector: " + $name)' "$HOMELAB_DEPLOYMENT_INDEX"
}

plan_changed_since() {
  local base="$1" file roots_json hosts_json root
  root="$(git rev-parse --show-toplevel)"
  base="$(git rev-parse --verify --end-of-options "${base}^{commit}")"
  git rev-parse --verify HEAD >/dev/null

  # Files, not process substitutions: every Git failure must reach set -e.
  # Disable rename detection so both the old and new owner's paths are planned.
  git -C "$root" diff --name-only --no-renames -z "$base"...HEAD -- >"$scratch/changed"
  git -C "$root" diff --name-only --no-renames -z HEAD -- >>"$scratch/changed"
  git -C "$root" diff --name-only --no-renames -z --cached HEAD -- >>"$scratch/changed"
  git -C "$root" ls-files --others --exclude-standard -z >"$scratch/untracked"
  untracked="$(jq -Rsc --argjson previous "$untracked" '$previous + (split("\u0000") | map(select(length > 0))) | unique' <"$scratch/untracked")"
  cat "$scratch/untracked" >>"$scratch/changed"
  sort -zu "$scratch/changed" >"$scratch/sorted"

  while IFS= read -r -d '' file; do
    roots_json="$(jq -c --arg file "$file" '
      (.sourceRoots + .machineRoots)
      | to_entries
      | map(.key as $root | select($file == $root or ($file | startswith($root + "/"))))
    ' "$HOMELAB_DEPLOYMENT_INDEX")"
    if [ "$roots_json" != '[]' ]; then
      hosts_json="$(jq -c '[.[].value[]] | unique' <<<"$roots_json")"
      add_hosts "$hosts_json" "changed:$file"
    else
      case "$file" in
        docs/*|README.md|AGENTS.md|CLAUDE.md|.github/*|tests/*)
          reason="$(jq -cn --argjson current "$reason" --arg why "docs-or-tests:$file" '$current + [$why]')"
          ;;
        *)
          hosts_json="$(jq -c '.allHosts' "$HOMELAB_DEPLOYMENT_INDEX")"
          add_hosts "$hosts_json" "conservative:$file"
          ;;
      esac
    fi
  done <"$scratch/sorted"
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

# Validate the generated boundary before interpreting it; null is not an empty plan.
jq -se '
  length == 1 and (.[0] | type == "object"
  and (.allHosts | type == "array")
  and (.targets | type == "object")
  and (.profiles | type == "object")
  and (.workloads | type == "object")
  and (.sourceRoots | type == "object")
  and (.machineRoots | type == "object")
  and (.activationOrder | type == "array"))
' "$HOMELAB_DEPLOYMENT_INDEX" >/dev/null || {
  echo "deployment-plan: invalid or unreadable deployment index: $HOMELAB_DEPLOYMENT_INDEX" >&2
  exit 1
}
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
untracked='[]'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --changed-since)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      plan_changed_since "$2"
      shift 2
      ;;
    --host)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      lookup targets "$2" >/dev/null
      hosts_json="$(jq -cn --arg host "$2" '[$host]')"
      add_hosts "$hosts_json" "host:$2"
      shift 2
      ;;
    --profile)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      hosts_json="$(lookup profiles "$2")"
      add_hosts "$hosts_json" "profile:$2"
      shift 2
      ;;
    --workload)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      hosts_json="$(lookup workloads "$2")"
      add_hosts "$hosts_json" "workload:$2"
      shift 2
      ;;
    --all)
      hosts_json="$(jq -c '.allHosts' "$HOMELAB_DEPLOYMENT_INDEX")"
      add_hosts "$hosts_json" "all"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "deployment-plan: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$untracked" != '[]' ]; then
  echo 'deployment-plan: untracked files affect this plan but Git-backed Nix flakes exclude them; review and git add intended source files before building. See untrackedFiles.' >&2
fi

jq -n \
  --argjson untracked "$untracked" \
  --slurpfile index "$HOMELAB_DEPLOYMENT_INDEX" \
  --argjson hosts "$selected" \
  --argjson reasons "$reason" '
    ($index[0]) as $i
    | {
        hosts: $hosts,
        untrackedFiles: $untracked,
        reasons: ($reasons | unique),
        builds: [
          $hosts[] as $host
          | select($i.targets[$host].buildAttribute != null)
          | ".#" + $i.targets[$host].buildAttribute
        ],
        plans: [
          $hosts[] as $host
          | select($i.targets[$host].planCommand != null)
          | $i.targets[$host].planCommand
        ],
        applies: [
          $hosts[] as $host
          | select($i.targets[$host].applyCommand != null)
          | $i.targets[$host].applyCommand
        ],
        verifies: [
          $hosts[] as $host
          | select($i.targets[$host].verifyCommand != null)
          | $i.targets[$host].verifyCommand
        ],
        activationOrder: [
          $i.activationOrder[]
          | select(. as $host | $hosts | index($host))
        ]
      }
  '
