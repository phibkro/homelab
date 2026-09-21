---
summary: Join declared inventory, current observations, and dated recovery evidence in one read-only operator CLI.
date: 2026-09-21
status: accepted
owner: operator
---

# Inventory-derived operator view

## Goal

One command shows what each active service is, where it runs, how it is reached,
who deploys it, whether its declared probe is healthy, what backup intent exists,
and which recovery evidence is accepted.

The view is a derivation. It does not become a service registry, monitoring
store, recovery ledger, or mutation surface.

## User journey

1. Run `nix run .#operator-view` from the homelab repository.
2. Read one compact row per active service workload.
3. Distinguish declared configuration from current runtime observations and
   dated recovery evidence.
4. Use `nix run .#operator-view -- --json` when another tool needs the complete
   structured snapshot.
5. See `unknown`, `unmonitored`, or `not-applicable` when the source cannot
   support a stronger claim.

No browser service, authentication lifecycle, database, or administrative
control is added in this version.

## Sources of truth

### Declared

- `lib.noriInventory.workloads` owns service identity and placement.
- `lib.noriInventory.routes` owns resolved route, audience, authentication, and
  monitoring declarations.
- `lib.noriDeployment.targets` owns deployment mechanism by host.
- Evaluated `nori.backups` jobs and `inventory/backup.nix` own backup intent and
  targets.

### Observed

- VictoriaMetrics' current `gatus_results_endpoint_success` series supplies
  route-probe health and sample timestamps.
- Backup unit completion supplies the last successful backup execution time.
  This is labeled as unit evidence, not direct repository inspection.
- Pi's `pi-restic-freshness.service` is stronger aggregate evidence because it
  inspects every remote Pi repository against its freshness budget.

A missing source, unreachable host, undeclared probe, or stale result remains
explicitly unknown. The command continues rendering other services when one
observation source is unavailable.

### Proven

`lib.noriRecoveryEvidence` supplies report references and accepted historical
gates. Those records never imply current health or backup freshness.

## Projection

The generated declaration contains one entry for every active workload whose
kind is `service`. Each entry contains:

- stable workload ID.
- resolved host or hosts.
- deployment owner from each host's deployment kind.
- zero or more routes with the canonical hostname and authentication method.
- zero or more canonical Gatus probe names.
- evaluated backup jobs, targets, or an explicit skip reason.
- recovery model, backup job, and related evidence records.

Route-less agents and background services remain in the view. Their route and
health fields are empty or unmonitored rather than fabricated.

The runtime snapshot has three separate objects per service:

```text
declared  — current repository configuration
observed  — timestamped health and backup observations
proven    — dated report references and historical gates
```

## Interface

Default output is a terminal table optimized for scanning. `--json` emits the
complete snapshot without ANSI formatting. The command is read-only and does
not require service credentials. SSH probes use batch mode and canonical host
IDs. A connection failure produces an unknown observation.

## Acceptance gates

- The generated declaration covers every active service workload exactly once.
- Host, route, authentication, deployment owner, backup intent, and recovery
  references derive from their existing authorities.
- Current Gatus health joins by the inventory-derived probe name and retains the
  observation timestamp.
- Source calls have time limits. Missing, malformed, stale, or future samples
  produce `unknown` instead of a stronger state.
- Unmonitored services remain explicit rather than disappearing.
- Backup observations state their source and do not claim direct snapshot
  inspection when only unit evidence exists.
- A failed runtime source does not suppress declared or proven data.
- JSON output is schema-versioned and parseable.
- The real command runs against the live homelab and reports the current state.
- Repository checks pass.
