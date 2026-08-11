# Plan 014: Run runtime tests in one pinned tool environment

> **Executor instructions**: Execute this plan last among the runtime-test plans. Preserve every test's behavior and diagnostics while changing only tool provisioning and process structure. Capture warm-cache timing before and after; do not claim a performance win without measurements.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- tests/tests.just tests/runtime flake.nix Justfile docs/reference/testing-methodology.md docs/reference/runtime-tests.md`

## Status

- **Priority**: P3
- **Effort**: M–L
- **Risk**: LOW
- **Depends on**: `plans/006-fail-closed-backup-runtime-tests.md`, `plans/008-run-replica-verifiers-now.md`, `plans/010-fail-closed-observability.md`, `plans/012-verify-authelia-client-registry.md`, `plans/013-repair-active-documentation.md`
- **Category**: perf, dx
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

Runtime recipes repeatedly invoke `nix shell nixpkgs#jq`, `nix shell nixpkgs#dig`, and `nix shell nixpkgs#restic` inside per-route and per-repository loops. Nix evaluation and shell startup can dominate the network and systemd probes, and the composite starts this overhead again in every subrecipe. That conflicts with the documented sub-30-second runtime-test budget.

Create one pinned runtime-test environment, move recipe bodies into executable scripts, and make the composite enter the environment once. Individual tests remain directly runnable through thin Just wrappers.

## Current state

Examples in `tests/tests.just`:

- route declaration and Caddy parsing invoke `nix shell ... jq` at lines 130-150;
- every DNS lookup invokes `nix shell ... dig` at line 166;
- every backup snapshot query invokes separate restic and jq shells at lines 321-324;
- hardening and fs loops repeatedly invoke jq at lines 417-494;
- the composite at lines 102-111 calls each public recipe, multiplying startup overhead.

Base system packages include `dig` but not the full runtime-test toolset (`modules/machines/base/base.nix:98-109`). Do not solve this by globally installing every test dependency on every host; provision a concern-specific environment.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Baseline timing | `/usr/bin/time -f '%e' just test` | record warm-cache wall time |
| Build environment | `nix develop .#runtime-tests --command true` | exit 0 |
| Search nested shells | `rg 'nix shell nixpkgs#' tests/tests.just tests/runtime` | no matches after migration |
| Run one test | `just test-routes` | behavior unchanged |
| Composite | `just test` | all runtime/eval tests pass |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `tests/tests.just`
- `tests/runtime/` — create/move executable runtime scripts here; preserve Plan 006's helpers
- `flake.nix`
- `Justfile` — import/wrapper adjustments only if required
- `docs/reference/testing-methodology.md`
- `docs/reference/runtime-tests.md`
- `plans/014-single-runtime-test-environment.md` — append execution measurements and final acceptance/rejection outcome

**Out of scope**:

- Changing assertions, thresholds, routes, backup semantics, or auth behavior.
- Adding test tools to global `environment.systemPackages` or user core.
- Rewriting tests in another language.
- Parallelizing stateful runtime tests; several intentionally mutate compositor state or start oneshots.
- Optimizing NixOS VM checks.

## Git workflow

- Execute after Plans 006, 008, 010, and 012 to avoid editing stale recipe bodies.
- Use an isolated worktree.
- Suggested commits:
  1. `refactor(tests): extract runtime probe scripts`
  2. `perf(tests): share pinned tool environment`

## Steps

### Step 1: Measure the current warm-cache baseline

On workstation, with the current deployment healthy, run the composite four times; discard run 1 and compute the median of runs 2–4. Do the same for `test-routes`, `test-backups`, and `test-harden`:

```bash
for i in 1 2 3 4; do
  /usr/bin/time -f "$i %e" -o "/tmp/runtime-test-baseline-$i.time" just test
done
```

Use the same command shape with each individual recipe. Record all raw values and medians in a new `## Execution measurements` section appended to this plan file when executing; that file is the durable evidence even when commits are not authorized.

If the current suite is red, STOP and resolve/report the correctness failure before performance refactoring.

### Step 2: Define a pinned `runtime-tests` dev shell

In `flake.nix`, add `devShells.x86_64-linux.runtime-tests` with exactly the tools used by runtime scripts, including:

- Bash/coreutils/findutils/gnugrep/gnused/gawk;
- curl;
- jq;
- bind DNS utilities;
- OpenSSH client;
- restic;
- systemd client tools if not inherited from the host;
- YAML parser required by Plan 012.

Set an environment marker such as `NORI_RUNTIME_TEST_ENV=1`. Do not include Hyprland/systemd daemon binaries that must come from the live host unless the script only needs their CLI and pinning it is compatible with the running daemon.

**Verify**:

```bash
nix develop .#runtime-tests --command bash -c \
  'command -v jq dig restic curl ssh >/dev/null && test "$NORI_RUNTIME_TEST_ENV" = 1'
```

Expected: exit 0.

### Step 3: Extract runtime recipe bodies into scripts

Move each layer-3 recipe body into a named executable under `tests/runtime/`, for example:

```text
observability.sh
routes.sh
authelia.sh
backups.sh
replicas.sh
harden.sh
fs.sh
hypr.sh
all.sh
```

Requirements:

- scripts use `#!/usr/bin/env bash` and `set -euo pipefail`;
- they source shared assertions relative to their own file location, not caller cwd;
- they invoke `jq`, `dig`, `restic`, etc. directly from the dev-shell PATH;
- they retain existing output, failure aggregation, and side-effect cleanup;
- `all.sh` invokes scripts directly and sequentially in the same environment;
- eval tests may remain a final `nix build` step because they are Nix operations, not tool-resolution loops.

Do not change test logic while moving it. Use byte-oriented diff/review to confirm assertions and thresholds are preserved.

### Step 4: Replace Just recipes with environment-aware wrappers

Each public recipe should remain available with its current name. Use a shared wrapper pattern:

- if `NORI_RUNTIME_TEST_ENV=1`, execute the corresponding script directly;
- otherwise enter `nix develop .#runtime-tests --command ...` once.

The composite `just test` must enter the dev shell once and run `tests/runtime/all.sh`; it must not call wrappers that each re-enter Nix.

Avoid recursive wrapper loops by checking the marker.

**Verify**:

```bash
just --summary
rg 'nix shell nixpkgs#' tests/tests.just tests/runtime
```

Expected: all recipe names remain; nested `nix shell nixpkgs#...` calls are absent.

### Step 5: Run behavior-preservation gates

Run each test individually through its public recipe, then the composite:

```bash
just test-routes
just test-backups
just test-observability
just test-replicas
just test-authelia
just test-harden
just test-fs
just test-hypr
just test-eval
just test
```

Expected: same healthy outcomes as before. Confirm Hypr paired toggles leave the session state unchanged.

### Step 6: Measure and report the result

Repeat the same timing commands from Step 1, warm cache. Acceptance criteria, computed from the median of warm runs 2–4 before and after:

- composite performs at most one `nix develop` startup;
- no per-item Nix shell startup remains;
- composite median improves by **at least 15% or at least 10 seconds**;
- for each individually measured recipe, regression is unacceptable only when it is both greater than 10% **and** greater than 2 seconds.

If the composite threshold is not met, or any individual recipe exceeds the regression threshold, revert this plan's implementation changes and mark the plan `REJECTED — measured benefit did not justify structure`, unless the operator explicitly accepts the measured trade-off in writing. Do not retain the extraction solely for aesthetic cleanup.

### Step 7: Update documentation and run full gate

Update testing docs with:

- the pinned runtime-tests environment;
- individual wrapper vs one-shell composite behavior;
- where runtime scripts and shared assertions live;
- how to add a dependency once to the dev shell.

Run:

```bash
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- Tool availability test inside `nix develop .#runtime-tests`.
- Every existing public recipe runs unchanged.
- Composite enters environment once.
- Search guarantees no nested ad-hoc `nix shell nixpkgs#` remains.
- Before/after warm-cache timings recorded.
- Full flake gate.

## Done criteria

- [ ] Runtime tools have one pinned environment.
- [ ] Public Just recipe names and behavior are preserved.
- [ ] Composite uses one environment startup.
- [ ] Per-route/per-repo Nix shell invocations are gone.
- [ ] Shared assertion helpers remain the single source from Plans 006/012.
- [ ] Median warm-cache composite improves by ≥15% or ≥10s, and no individual recipe exceeds the >10% and >2s regression threshold; otherwise the refactor is rejected/reverted or explicitly operator-approved.
- [ ] Every runtime recipe and full flake check pass.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- any prerequisite runtime-test plan is incomplete;
- the baseline suite is red;
- moving scripts changes test semantics or cleanup behavior;
- Hyprland client version must match the compositor and cannot safely come from the dev shell;
- one-shell execution causes environment leakage between tests;
- measured performance misses the numeric acceptance thresholds and the operator has not explicitly accepted the trade-off.

## Maintenance notes

- Add future runtime-test dependencies to the `runtime-tests` shell once, never via per-call `nix shell`.
- Correctness remains the authority: performance refactoring is accepted only with identical outcomes and measured benefit.
- Keep scripts concern-oriented; do not create a general test framework beyond the shared helpers that current tests need.
