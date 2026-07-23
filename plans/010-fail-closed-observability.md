# Plan 010: Fail closed when heartbeat or disk-alert delivery cannot be observed

> **Executor instructions**: This plan intentionally converts uncertainty into a red test or failed unit. Do not restore green by swallowing network errors. Add bounded retry so transient notification outages are tolerable without becoming invisible.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- tests/tests.just modules/infra/observability/disk-alert.nix tests/e2e-disk-alert.nix docs/reference/runtime-tests.md`

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: MED
- **Depends on**: `plans/006-fail-closed-backup-runtime-tests.md`, `plans/008-run-replica-verifiers-now.md` (shared runtime helpers and `tests/tests.just`)
- **Category**: bug, tests
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

The monitoring plane currently has two false-green paths. `test-observability` prints that heartbeat state is unreadable but does not fail. `disk-alert.service` suppresses a failed ntfy POST with `|| true`, so the unit succeeds and its `OnFailure` path never activates. In both cases the inability to observe or deliver the alert is treated as success.

Make read failures red, make delivery bounded and explicit, and test both the successful POST and unavailable-receiver paths.

## Current state

```bash
# tests/tests.just:66-79
last=$(ssh ...)
uptime_us=$(ssh ...)
...
else
  echo "· heartbeat state unreadable ..."
fi
```

```nix
# modules/infra/observability/disk-alert.nix:77-108
unitConfig.OnFailure = [ "notify@disk-alert.service" ];
...
curl -fsS ... "$url" || true
```

- The heartbeat timer runs every 60 seconds; the recipe allows 90 seconds.
- `tests/e2e-disk-alert.nix:100-177` already runs a real local HTTP receiver and verifies the successful alert shape.
- The `notify@` fallback uses the same ntfy plane, so it may also fail during a total ntfy outage; that is acceptable as long as systemd records both failures and no recursive loop exists.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Focused VM test | `nix build --no-link .#checks.x86_64-linux.e2e-disk-alert` | success and failure-path subtests pass |
| Pi build | `nix build --no-link .#nixosConfigurations.pi.config.system.build.toplevel` | exit 0 |
| Runtime probe | `just test-observability` | all observations readable and healthy |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `tests/tests.just`
- `tests/runtime/assertions.sh`
- `tests/runtime/assertions.test.sh`
- `modules/infra/observability/disk-alert.nix`
- `tests/e2e-disk-alert.nix`
- `docs/reference/runtime-tests.md`

**Out of scope**:

- Replacing ntfy, changing alert thresholds, or adding a second alert provider.
- Changing heartbeat cadence or VictoriaMetrics queries.
- Cross-host maintenance silencing; that is separately deferred in the roadmap.
- Making monitoring tests tolerant of unreadable state.

## Git workflow

- Use an isolated worktree when dispatched.
- Do not deliberately stop production ntfy for verification.
- Suggested commit: `fix(observability): surface unreadable and undelivered alerts`.

## Steps

### Step 1: Make heartbeat observation errors fail

Extend Plan 006's `tests/runtime/assertions.sh` with:

1. pure `heartbeat_age_ok <last_monotonic_us> <uptime_us> <budget_seconds>` — reject empty, zero, non-numeric, future, and over-budget values; on success print the computed age only;
2. `heartbeat_probe <ssh-executable> <target> <budget-seconds>` — run the two fixed remote commands with `ConnectTimeout=3`, capture each status explicitly, label timestamp-vs-uptime failures, and call `heartbeat_age_ok` only when both observations succeed.

`test-observability` must call the exact shared function inside an `if ! heartbeat_probe ...; then fail=1; fi` branch so strict shell mode cannot terminate before the composite failure report.

In `assertions.test.sh`, create a temporary fake SSH executable and drive it with a fixture mode variable. Required modes:

- both commands return recent valid values → `heartbeat_probe` succeeds;
- timestamp command returns nonzero → function fails and diagnostic names timestamp query;
- timestamp succeeds but uptime command returns nonzero → function fails and diagnostic names uptime query;
- stale, empty, zero, non-numeric, and future values → function fails through `heartbeat_age_ok`.

The fake SSH script must inspect the final remote-command argument and never contact a network.

Do not fall back to VictoriaMetrics for this same assertion: the test intentionally checks the live heartbeat unit independently of the downstream metrics plane.

**Verify**:

```bash
bash tests/runtime/assertions.test.sh
just --show test-observability | grep -E 'heartbeat_probe|fail=1'
```

Expected: all fake-SSH and value fixtures pass by observing the required success/failure, and the live recipe uses the tested function.

### Step 2: Give disk-alert delivery bounded retries and real failure semantics

Replace `curl ... || true` with a bounded call using the pinned curl options supported by NixOS 26.05, for example:

```bash
curl -fsS \
  --retry 3 \
  --retry-all-errors \
  --retry-delay 2 \
  --connect-timeout 5 \
  --max-time 15 \
  ...
```

Let final failure propagate out of the pipeline and service. Because the curl runs inside a `df | while` pipeline, ensure shell semantics actually propagate the loop's failure. Avoid a subshell pipeline if necessary: use process substitution or capture `df` output before the loop.

Keep `OnFailure = [ "notify@disk-alert.service" ]`. Confirm `notify@` has no `OnFailure` pointing back to disk-alert, preventing recursion.

**Verify**:

```bash
nix eval --raw .#nixosConfigurations.pi.config.systemd.services.disk-alert.script | \
  grep -E 'retry-all-errors|max-time'
```

Expected: bounded retry options present and no `|| true` after the alert POST.

### Step 3: Extend the E2E test with receiver failure

In `tests/e2e-disk-alert.nix`, preserve the existing success subtest, then add:

1. stop `test-ntfy-receiver.service`;
2. start `disk-alert.service` expecting failure;
3. assert `Result=exit-code` or the pinned systemd equivalent;
4. assert the service journal contains a curl delivery failure;
5. assert the unit does not remain activating or enter a restart loop;
6. optionally assert `notify@disk-alert.service` is attempted once, without requiring it to succeed against the stopped receiver.

Keep retry durations low enough that the whole NixOS test stays inside the documented five-minute budget. Override retry count/delay through module options only if a reusable operational knob is justified; otherwise use the production bounded values.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.e2e-disk-alert
```

Expected: successful delivery and failed-delivery subtests both pass.

### Step 4: Run build and live observation gates

```bash
nix build --no-link .#nixosConfigurations.pi.config.system.build.toplevel
nix flake check --print-build-logs
just test-observability
```

Expected: all pass. If `just test-observability` now exposes a real SSH/heartbeat problem, report it; do not suppress the result.

After deployment, observe one scheduled disk-alert run under normal disk usage. Do not force the production threshold or stop ntfy.

### Step 5: Update runtime-test documentation

Document that:

- unreadable observation is failure;
- disk-alert final delivery failure fails the unit after bounded retry;
- `OnFailure` is secondary evidence, not a reason to return success from the primary unit.

**Verify**:

```bash
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- `assertions.test.sh`: recent, stale, empty, zero, non-numeric, and future heartbeat values plus fake-SSH timestamp-query and uptime-query failures.
- `test-observability`: calls the same tested `heartbeat_probe` function and aggregates its nonzero result into the final failure report.
- `e2e-disk-alert`:
  - receiver active → correct POST and unit success;
  - receiver stopped → bounded delay, unit failure, no loop.
- Pi closure build and full flake gate.

## Done criteria

- [ ] Unreadable heartbeat state fails the runtime test.
- [ ] Disk-alert uses bounded retry and propagates final POST failure.
- [ ] Pipeline structure does not swallow curl status.
- [ ] E2E covers both receiver-up and receiver-down paths.
- [ ] Pi build, focused E2E, runtime probe, and full gate pass.
- [ ] No production alert service is deliberately stopped during verification.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- the curl options are unavailable in the pinned version;
- `OnFailure` creates a recursive dependency or restart loop;
- bounded retry pushes the E2E test beyond five minutes;
- the strengthened heartbeat test reveals a real live monitoring outage;
- fixing pipeline status requires changing disk threshold semantics.

## Maintenance notes

- Monitoring code has one rule: failure to observe is not evidence of health.
- Reviewers should inspect shell pipeline exit propagation; `set -e` alone is not sufficient across every loop/subshell shape.
