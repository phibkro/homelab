---
date: 2026-09-21
status: frozen
---

# Pi recovery evidence closure

## Goal

Every state-bearing Pi workload and every Pi backup repository has accepted,
reproducible recovery evidence. An operator can distinguish application recovery
from repository integrity and from physical-host acceptance.

## User journey

1. Run the generated recovery view.
2. See an explicit recovery contract for each state-bearing Pi workload.
3. Follow the linked dated evidence for each accepted recovery claim.
4. Confirm that each of the eight Pi repositories completed a full data-block
   check.
5. Confirm that each disposable recovery container and restore directory was
   removed without changing the live service.

## Constraints

- `inventory/backup.nix` remains the authority for Pi backup jobs and paths.
- Workload manifests own application recovery models.
- `inventory/recovery-evidence.nix` owns accepted evidence links and gates.
- Restore drills use the deployed root-only disposable restore helper.
- Recovered services bind only to loopback test ports.
- Current declarative configuration and secrets can be reused read-only when
  they are not part of the backup. Reports must state that dependency.
- Existing snapshots and live service state must not be changed.
- Physical power-cycle, off-LAN, and Tailscale control-plane acceptance remain
  operator-only boundaries.

## Acceptance gates

- Caddy: restore state, validate the recovered configuration/state combination,
  and start or otherwise exercise the recovered state without claiming a public
  listener.
- Beszel: restore PocketBase state, verify database integrity, start an isolated
  container, and receive a successful health response.
- VictoriaMetrics: restore its data and configuration, start an isolated
  container, receive health, and execute a read query.
- VictoriaLogs: restore its data, start an isolated container, receive health,
  and execute a read query.
- Vector: restore checkpoints and configuration, validate configuration, and
  start an isolated sender against the isolated VictoriaLogs receiver when
  safe.
- All eight repositories complete `restic check --read-data` or an equivalent
  100 percent data-pack read using the deployed pinned transport.
- The generated recovery matrix contains the new contracts and evidence.
- Repository validation passes and the dated report records snapshot IDs,
  results, cleanup, and unproved limits.
