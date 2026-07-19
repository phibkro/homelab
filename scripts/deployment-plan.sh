#!/usr/bin/env bash
set -euo pipefail

: "${HOMELAB_DEPLOYMENT_INDEX:?HOMELAB_DEPLOYMENT_INDEX must point to the generated deployment index}"

usage() {
  cat <<'EOF'
usage: deployment-plan [selectors]

Selectors may be repeated and are unioned:
  --changed-since REF   derive targets from committed and working-tree changes
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
  local base="$1" file matched roots_json
  mapfile -t changed < <(
    {
      git diff --name-only "$base"...HEAD
      git diff --name-only HEAD
      git diff --name-only --cached HEAD
    } | sort -u
  )

  for file in "${changed[@]}"; do
    [ -n "$file" ] || continue
    matched=false

    while IFS= read -r roots_json; do
      [ -n "$roots_json" ] || continue
      add_hosts "$(jq -c '.value' <<<"$roots_json")" "changed:$file"
      matched=true
    done < <(
      jq -c --arg file "$file" '
        (.sourceRoots + .machineRoots)
        | to_entries[]
        | .key as $root
        | select($file == $root or ($file | startswith($root + "/")))
      ' "$HOMELAB_DEPLOYMENT_INDEX"
    )

    if [ "$matched" = false ]; then
      case "$file" in
        docs/*|README.md|AGENTS.md|CLAUDE.md|.github/*|tests/*)
          reason="$(jq -cn --argjson current "$reason" --arg why "docs-or-tests:$file" '$current + [$why]')"
          ;;
        *)
          add_hosts "$(jq -c '.allHosts' "$HOMELAB_DEPLOYMENT_INDEX")" "conservative:$file"
          ;;
      esac
    fi
  done
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

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
      add_hosts "$(jq -cn --arg host "$2" '[$host]')" "host:$2"
      shift 2
      ;;
    --profile)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      add_hosts "$(lookup profiles "$2")" "profile:$2"
      shift 2
      ;;
    --workload)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      add_hosts "$(lookup workloads "$2")" "workload:$2"
      shift 2
      ;;
    --all)
      add_hosts "$(jq -c '.allHosts' "$HOMELAB_DEPLOYMENT_INDEX")" "all"
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

jq -n \
  --slurpfile index "$HOMELAB_DEPLOYMENT_INDEX" \
  --argjson hosts "$selected" \
  --argjson reasons "$reason" '
    ($index[0]) as $i
    | {
        hosts: $hosts,
        reasons: ($reasons | unique),
        builds: [
          $hosts[] as $host
          | ".#" + $i.targets[$host].buildAttribute
        ],
        activationOrder: [
          $i.activationOrder[]
          | select(. as $host | $hosts | index($host))
        ]
      }
  '
