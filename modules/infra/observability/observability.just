#!/usr/bin/env just --justfile
# Operator-facing recipes for the observability concern (logs + metrics).
# Imported via the root Justfile.
#
# Health checks live in `tests/tests.just § test-observability` (scrape
# targets up, per-host series, pi heartbeat, gatus probes).
#
# Pi tailnet IP (100.100.71.3) is hardcoded here — stable; avoids an
# extra nix-eval per invocation. If pi's tailnet identity ever changes,
# update here + in tests/tests.just simultaneously.

# Tail recent journal lines for a unit. Usage: just show-logs <unit>
@show-logs unit:
    sudo journalctl -u {{unit}} -n 50 --no-pager

# Live-tail a unit. Usage: just follow <unit>
@follow unit:
    sudo journalctl -u {{unit}} -f

# See .claude/skills/query-logs/SKILL.md for syntax.
#
# Usage:
#   just query-logs 'unit:ollama.service priority:<=3 | head 20'
#   just query-logs 'level:error | _time:1h | stats by (unit) count()'
#
# Query the central VictoriaLogs index via LogsQL. Cross-host, fan-out included.
@query-logs query:
    curl -sG "http://100.100.71.3:9428/select/logsql/query" \
        --data-urlencode 'query={{query}}' \
      | (command -v jq >/dev/null && jq . || cat)
