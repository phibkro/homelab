# Runtime observer for the generated operator-view declaration.
# This file is embedded by src/lib/flake-parts/packages/operator-view.nix.

output_format="table"
if (( $# > 1 )); then
  printf 'operator-view: expected at most one argument\n' >&2
  exit 2
fi

case "${1:-}" in
  "") ;;
  --json) output_format="json" ;;
  --help|-h)
    printf '%s\n' \
      'Usage: operator-view [--json]' \
      '' \
      'Show declared services, current health and backup observations, and' \
      'accepted recovery evidence. The command is read-only.'
    exit 0
    ;;
  *)
    printf 'operator-view: unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
esac

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
health_records="$work_dir/health.json"
health_source="$work_dir/health-source.json"
backup_lines="$work_dir/backups.ndjson"
backup_records="$work_dir/backups.json"
snapshot="$work_dir/snapshot.json"
: >"$backup_lines"

health_url=$(jq -r '.healthSource.url' "$OPERATOR_VIEW_DECLARATION")
health_metric=$(jq -r '.healthSource.metric' "$OPERATOR_VIEW_DECLARATION")
health_max_age=$(jq -r '.healthSource.maxAgeSeconds' "$OPERATOR_VIEW_DECLARATION")
if [[ "$health_url" == "null" ]]; then
  health_endpoint=""
else
  health_endpoint="${health_url%/}/api/v1/query"
fi
health_error="$work_dir/health-error"

if [[ "$health_url" != "null" ]] \
  && health_response=$(curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    --get "$health_endpoint" --data-urlencode "query=$health_metric" 2>"$health_error") \
  && jq -e '
    .status == "success"
    and (.data.result | type) == "array"
    and all(.data.result[];
      (.metric.key | type) == "string"
      and (.value | type) == "array"
      and (.value | length) >= 2
      and ((try (.value[0] | tonumber | floor | todateiso8601) catch null) != null)
      and (.value[1] == "0" or .value[1] == "1")
    )
  ' >/dev/null <<<"$health_response"; then
  jq '[
    .data.result[]
    | select(.metric.key != null and .value[0] != null and .value[1] != null)
    | {
        key: (.metric.key | ltrimstr("_")),
        success: (.value[1] == "1"),
        observedEpoch: (.value[0] | tonumber),
        observedAt: (.value[0] | tonumber | floor | todateiso8601)
      }
  ] | group_by(.key) | map(max_by(.observedEpoch))' \
    <<<"$health_response" >"$health_records"
  jq -n --arg url "$health_endpoint" --argjson maxAgeSeconds "$health_max_age" \
    '{status: "ok", url: $url, maxAgeSeconds: $maxAgeSeconds}' >"$health_source"
else
  printf '[]\n' >"$health_records"
  if [[ "$health_url" == "null" ]]; then
    health_message="health source not declared"
  else
    health_message=$(tr '\n' ' ' <"$health_error")
    if [[ -z "$health_message" ]]; then
      health_message="invalid response"
    fi
  fi
  jq -n --arg url "$health_endpoint" --arg error "$health_message" \
    --argjson maxAgeSeconds "$health_max_age" \
    '{
      status: "unavailable",
      url: (if $url == "" then null else $url end),
      maxAgeSeconds: $maxAgeSeconds,
      error: $error
    }' >"$health_source"
fi

now_epoch=$(date +%s)
local_host=$(hostname --short)
observe_unit() {
  local host=$1
  local unit=$2
  local source=$3
  local raw result observed_at observed_epoch state error_file error_message

  if [[ ! "$unit" =~ ^[A-Za-z0-9@_.-]+\.service$ ]]; then
    jq -nc --arg host "$host" --arg unit "$unit" --arg source "$source" \
      '{
        host: $host,
        unit: $unit,
        source: $source,
        state: "unknown",
        result: null,
        observedAt: null,
        observedEpoch: null,
        error: "invalid unit name"
      }' \
      >>"$backup_lines"
    return
  fi

  error_file="$work_dir/unit-error-${host}-${unit}"
  if [[ "$host" == "$local_host" ]]; then
    if ! raw=$(timeout 10s systemctl show "$unit" --no-pager \
      --property=Result --property=InactiveExitTimestamp 2>"$error_file"); then
      raw=""
    fi
  else
    if ! raw=$(timeout 10s ssh -n -o BatchMode=yes -o ConnectTimeout=5 "nori@${host}" \
      systemctl show "$unit" --no-pager \
      --property=Result --property=InactiveExitTimestamp 2>"$error_file"); then
      raw=""
    fi
  fi

  if [[ -z "$raw" ]]; then
    error_message=$(tr '\n' ' ' <"$error_file")
    if [[ -z "$error_message" ]]; then
      error_message="unit state unavailable"
    fi
    jq -nc --arg host "$host" --arg unit "$unit" --arg source "$source" \
      --arg error "$error_message" \
      '{
        host: $host,
        unit: $unit,
        source: $source,
        state: "unknown",
        result: null,
        observedAt: null,
        observedEpoch: null,
        error: $error
      }' \
      >>"$backup_lines"
    return
  fi

  result=$(jq -Rr 'select(startswith("Result=")) | sub("^Result="; "")' <<<"$raw")
  observed_at=$(jq -Rr 'select(startswith("InactiveExitTimestamp=")) | sub("^InactiveExitTimestamp="; "")' <<<"$raw")
  observed_epoch=""
  if [[ -n "$observed_at" ]]; then
    observed_epoch=$(date --date="$observed_at" +%s 2>/dev/null || true)
  fi
  error_message=""

  if [[ -n "$observed_epoch" && "$observed_epoch" -gt "$now_epoch" ]]; then
    state="unknown"
    error_message="future completion timestamp"
  elif [[ "$result" == "success" && -n "$observed_epoch" && "$source" == "repository-freshness-check" ]]; then
    state="fresh-at-last-check"
  elif [[ "$result" == "success" && -n "$observed_epoch" ]]; then
    state="last-run-success"
  elif [[ -n "$result" && -n "$observed_epoch" ]]; then
    state="failed"
  else
    state="unknown"
    error_message="missing or unparseable completion timestamp"
  fi

  jq -nc \
    --arg host "$host" \
    --arg unit "$unit" \
    --arg source "$source" \
    --arg state "$state" \
    --arg result "$result" \
    --arg observedAt "$observed_at" \
    --arg observedEpoch "$observed_epoch" \
    --arg error "$error_message" \
    '{
      host: $host,
      unit: $unit,
      source: $source,
      state: $state,
      result: (if $result == "" then null else $result end),
      observedAt: (if $observedAt == "" then null else $observedAt end),
      observedEpoch: (if $observedEpoch == "" then null else ($observedEpoch | tonumber) end),
      error: (if $error == "" then null else $error end)
    }' >>"$backup_lines"
}

backup_plan="$work_dir/backup-plan.tsv"
jq -r '[
  .services[].declared.backups[]
  | select(.state == "active")
  | . as $backup
  | .observationUnits[]
  | [$backup.host, ., $backup.observationSource]
] | unique | .[] | @tsv' "$OPERATOR_VIEW_DECLARATION" >"$backup_plan"

while IFS=$'\t' read -r host unit source; do
  observe_unit "$host" "$unit" "$source"
done <"$backup_plan"

jq -s '.' "$backup_lines" >"$backup_records"
generated_at=$(date --utc --iso-8601=seconds)

jq -n \
  --slurpfile declaration "$OPERATOR_VIEW_DECLARATION" \
  --slurpfile health "$health_records" \
  --slurpfile healthSource "$health_source" \
  --slurpfile backupObservations "$backup_records" \
  --arg generatedAt "$generated_at" \
  --argjson nowEpoch "$now_epoch" \
  --argjson healthMaxAgeSeconds "$health_max_age" '
  def health_for($service):
    [$service.declared.probes[] as $probe | $health[0][] | select(.key == $probe)] as $observations
    | [$observations[] | select(.observedEpoch > $nowEpoch)] as $future
    | [$observations[] | select(($nowEpoch - .observedEpoch) > $healthMaxAgeSeconds)] as $stale
    | if ($service.declared.probes | length) == 0 then
        {state: "unmonitored", probes: []}
      elif ($observations | length) != ($service.declared.probes | length) then
        {state: "unknown", reason: "missing", probes: $observations}
      elif ($future | length) > 0 then
        {state: "unknown", reason: "future", probes: $observations}
      elif ($stale | length) > 0 then
        {state: "unknown", reason: "stale", probes: $observations}
      elif all($observations[]; .success) then
        {state: "healthy", probes: $observations}
      else
        {state: "failing", probes: $observations}
      end;

  def observed_backups($service):
    [$service.declared.backups[]
      | . as $backup
      | . + {
          observations: [
            .observationUnits[] as $unit
            | $backupObservations[0][]
            | select(.host == $backup.host and .unit == $unit)
          ]
        }
    ];

  def backup_for($service):
    observed_backups($service) as $jobs
    | [$jobs[].observations[] | .observedEpoch | select(. != null and . <= $nowEpoch)] as $epochs
    | {
        state:
          if ($jobs | length) == 0 then "not-declared"
          elif any($jobs[]; .state == "active" and any(.observations[]; .state == "failed")) then "failed"
          elif any($jobs[]; .state == "active" and (.observationUnits | length) == 0) then "unknown"
          elif any($jobs[]; .state == "active" and (.observations | length) != (.observationUnits | length)) then "unknown"
          elif any($jobs[]; .state == "active" and any(.observations[]; .state == "unknown")) then "unknown"
          elif any($jobs[]; .state == "active") and any($jobs[]; .state == "disabled") then "partial"
          elif any($jobs[]; .state == "active" and .observationSource == "repository-freshness-check") then "fresh-at-last-check"
          elif any($jobs[]; .state == "active") then "last-run-success"
          elif any($jobs[]; .state == "disabled") then "not-active"
          else "not-applicable"
          end,
        ageSeconds: (if ($epochs | length) == 0 then null else ($nowEpoch - ($epochs | min)) end),
        jobs: $jobs
      };

  {
    schemaVersion: $declaration[0].schemaVersion,
    generatedAt: $generatedAt,
    sources: {
      health: $healthSource[0],
      backups: {
        status: (if any($backupObservations[0][]; .state == "unknown") then "partial" else "ok" end)
      }
    },
    services: [
      $declaration[0].services[]
      | . as $service
      | {
          id: .id,
          declared: .declared,
          observed: {
            health: health_for($service),
            backup: backup_for($service)
          },
          proven: .proven
        }
    ]
  }
' >"$snapshot"

if [[ "$output_format" == "json" ]]; then
  cat "$snapshot"
  exit 0
fi

jq -r '
  def joined: if length == 0 then "—" else join(",") end;
  def age:
    if . == null then ""
    elif . < 3600 then " \((. / 60) | floor)m"
    elif . < 86400 then " \((. / 3600) | floor)h"
    else " \((. / 86400) | floor)d"
    end;
  ["SERVICE", "HOST", "ROUTE", "AUTH", "HEALTH", "BACKUP", "OWNER", "RECOVERY"],
  (.services[] | [
    .id,
    (.declared.hosts | joined),
    ([.declared.routes[].hostname] | joined),
    ([.declared.routes[].authentication] | unique | joined),
    .observed.health.state,
    (.observed.backup.state + (.observed.backup.ageSeconds | age)),
    (.declared.deploymentOwners | unique | joined),
    ([.proven.recoveryEvidence[].id] | joined)
  ])
  | @tsv
' "$snapshot" | column --table --separator $'\t'
