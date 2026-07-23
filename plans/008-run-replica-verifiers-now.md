# Plan 008: Make replica tests run current verification instead of trusting stored success

> **Executor instructions**: Plan 005 must already be complete so workstation has target-side registry entries and verifier units. The verifier is read-only; invoke it during the test and inspect its current result. Do not weaken snapshot-age budgets to accommodate a stale deployment.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- tests/tests.just modules/infra/storage/replication.nix docs/reference/runtime-tests.md`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-place-replica-intent-on-target.md`, `plans/006-fail-closed-backup-runtime-tests.md` (serializes `tests/tests.just`)
- **Category**: bug, tests
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

`just test-replicas` currently accepts the last stored `Result=success`. Systemd retains that result even if the hourly timer stops firing, so a historical pass can remain green indefinitely. The verifier itself is a cheap read-only freshness check; the runtime test should execute it now and observe current data.

## Current state

```bash
# tests/tests.just:381-389
result=$(systemctl show -p Result --value "$unit" ...)
if [[ "$result" == "success" ]]; then
  echo "✓ ..."
fi
```

- `modules/infra/storage/replication.nix:141-163` defines a read-only script: inspect target directory, find newest snapshot mtime, compare with `maxAgeHours`.
- `modules/infra/storage/replication.nix:167-176` schedules the same verifier hourly.
- No replication or mutation occurs when starting the verifier service.
- After Plan 005, workstation should have five registry entries and five verifier units.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Inspect target units | `systemctl list-unit-files 'replication-verifier-*.service' --no-legend` | one per workstation-target replica |
| Runtime test | `just test-replicas` | every verifier run now and succeeds |
| Target build | `nix build --no-link .#nixosConfigurations.workstation.config.system.build.toplevel` | exit 0 |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `tests/tests.just`
- `modules/infra/storage/replication.nix` — comment or unit metadata only if needed
- `docs/reference/runtime-tests.md`

**Out of scope**:

- Replica registry placement; Plan 005 owns it.
- Running btrbk send/receive or changing snapshot data.
- Changing `maxAgeHours`, timer cadence, retention, or paths.
- Adding pavilion replication.

## Git workflow

- Use the isolated worktree supplied by the dispatcher.
- Starting verifier units is allowed because they are read-only; do not start the replication sender.
- Suggested commit: `fix(tests): run replica freshness verifiers synchronously`.

## Steps

### Step 1: Filter declarations to this target host before deciding whether to skip

Change `test-replicas` so it evaluates the registry once as JSON and uses `jq` to select entries whose `.target.host` equals `hostname`.

Rules:

- no entries targeting this host → print a precise skip message and exit 0;
- entries exist but no corresponding units → fail;
- do not treat “registry is globally non-empty” as work for every host.

**Verify**:

```bash
just --show test-replicas | grep -E 'target.host|no replicas targeting'
```

Expected: target-side filtering is explicit.

### Step 2: Verify the service and timer artifacts exist

For each target-side entry:

- require `replication-verifier-<name>.service` to exist;
- require `systemctl is-enabled replication-verifier-<name>.timer` to return exactly `enabled`;
- require `systemctl is-active replication-verifier-<name>.timer` to return exactly `active`;
- require `systemctl list-timers replication-verifier-<name>.timer --no-legend` to return one row containing that timer name.

Missing observation is failure, not skip.

**Verify**:

```bash
just --show test-replicas | grep -E 'is-enabled|list-timers|verifier unit missing'
```

Expected: service and timer checks are present.

### Step 3: Start each verifier synchronously

Run each read-only verifier now with explicit status capture:

```bash
start_rc=0
sudo systemctl start --wait "$unit" || start_rc=$?
result=$(systemctl show "$unit" -p Result --value 2>/dev/null || printf 'unreadable')
main_status=$(systemctl show "$unit" -p ExecMainStatus --value 2>/dev/null || printf 'unreadable')
if [[ "$start_rc" -ne 0 || "$result" != "success" || "$main_status" != "0" ]]; then
  echo "✗ $name: start_rc=$start_rc Result=$result ExecMainStatus=$main_status"
  journalctl -u "$unit" -n 100 --no-pager
  fail=1
  continue
fi
```

This pattern is required so `set -e` cannot terminate before diagnostics and so every verifier is attempted. Keep each property query separately labeled.

This replaces reliance on historical timestamps entirely. Do not add an age calculation for the verifier run itself; synchronous execution is stronger and simpler.

**Verify source shape**:

```bash
just --show test-replicas | grep -E 'start --wait|ExecMainStatus|journalctl'
```

Expected: all mechanisms are present and the old result-only branch is absent.

### Step 4: Run the current target journey

On workstation after Plan 005 is deployed:

```bash
just test-replicas
```

Expected: five verifier services run and report current snapshot ages within their declared budgets.

If a verifier reports stale or missing snapshots, STOP and report the exact dataset. Do not trigger btrbk or alter the budget in this plan.

### Step 5: Update docs and gates

Update `docs/reference/runtime-tests.md` to say `test-replicas` actively invokes each read-only verifier and checks timer registration; remove wording implying a stored service result is sufficient.

Run:

```bash
nix build --no-link .#nixosConfigurations.workstation.config.system.build.toplevel
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- Workstation with target entries: every verifier starts now.
- Pi/aurora/pavilion with no entries targeting themselves: explicit target-specific skip.
- Missing service or disabled timer: test fails.
- Stale/missing snapshot: verifier fails and test surfaces journal output.
- Healthy current snapshots: all pass.

## Done criteria

- [ ] The test filters registry entries by current target host.
- [ ] It checks service and timer existence.
- [ ] It synchronously runs every target verifier.
- [ ] Stored historical `Result=success` alone cannot pass.
- [ ] Workstation's live test checks all expected replicas.
- [ ] Workstation build and full flake check pass.
- [ ] Documentation matches behavior.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- Plan 005 is incomplete or workstation still evaluates an empty registry;
- a verifier performs mutation rather than the read-only script documented in `replication.nix`;
- live execution exposes stale/missing data;
- `systemctl start --wait` is unsupported by the deployed systemd;
- running as the operator cannot use sudo for the verifier without changing sudo policy.

## Maintenance notes

- A stored result is diagnostic history, not current evidence. Continue to prefer active observation for cheap read-only checks.
- Keep replication itself outside the test; the verifier is the safe boundary.
