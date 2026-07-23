# Plan 007: Resolve manual backups to generated job-target units

> **Executor instructions**: Preserve the `nori.backups` fan-out model. A logical job may have multiple target units; the manual command must either run all targets or an explicitly selected target. Do not recreate a synthetic bare unit unless the module architecture itself needs one.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- modules/infra/backup/backup.just docs/reference/services.md README.md`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug, dx
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

`just backup <repo>` targets `restic-backups-<repo>.service`, but the backup generator creates one unit per `(job,target)` pair: `restic-backups-<job>-<target>.service`. The documented out-of-cycle backup path therefore fails exactly when an operator needs it for verification or recovery preparation.

Make the recipe resolve live generated units, run every target by default, support an explicit target, and return only after each oneshot has a successful result.

## Current state

```just
# modules/infra/backup/backup.just:14-19
@backup repo:
    sudo systemctl start restic-backups-{{repo}}.service && \
      journalctl -u restic-backups-{{repo}}.service -f
```

```text
# modules/infra/backup/default.nix:53-56
services.restic.backups.<job>-<target>
restic-backups-<job>-<target>.service
```

Planning-time evaluation found only fan-out names such as `restic-backups-user-data-mp510` and `restic-backups-user-data-onetouch`; no bare job unit exists.

Conventions:

- Manual recipes live beside the concern in `modules/infra/backup/backup.just`.
- Commands must fail loud on ambiguity or absence.
- Avoid indefinite `journalctl -f` in automation; wait for the oneshot and print bounded logs on failure.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Parse Justfile | `just --summary` | exit 0; `backup` listed |
| Show expansion | `just --dry-run backup user-data` | generated resolver script shown |
| Enumerate units | `systemctl list-unit-files 'restic-backups-user-data-*.service' --no-legend` | one or more units |
| Live run | `just backup <small-job> <target>` | selected unit completes with `Result=success` |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `modules/infra/backup/backup.just`
- `docs/reference/services.md` — manual-trigger example only
- `README.md` — only if it documents the old invocation

**Out of scope**:

- Backup generation, schedules, retention, credentials, repositories, or restore drills.
- Creating an alias systemd unit.
- Starting a real backup without explicit operator approval.
- Changing `list-snapshots`; it has a separate single-target limitation that should be planned only if the operator requests it.

## Git workflow

- Use the dispatcher's isolated worktree when applicable.
- Do not run the live backup step without operator authorization.
- Suggested commit: `fix(backups): resolve manual job target units`.

## Steps

### Step 1: Replace the bare-unit recipe with a resolver

Change the recipe signature to accept a logical job and optional target:

```just
@backup job target="":
```

Use a Bash script body with `set -euo pipefail`.

Resolution rules:

- when `target` is non-empty, require exactly `restic-backups-${job}-${target}.service` to exist;
- when `target` is empty, enumerate `restic-backups-${job}-*.service` from `systemctl list-unit-files`;
- zero matches: fail with the job name and show matching available backup units;
- one or more matches: print the exact units before starting them;
- sort units for deterministic output.

Do not parse target names by stripping suffixes; ask systemd for the generated artifact directly.

**Verify**:

```bash
just --summary | grep -w backup
just --dry-run backup user-data
just --dry-run backup user-data mp510
```

Expected: all parse and show job-target resolution.

### Step 2: Wait for completion and inspect each result

Start each resolved oneshot with explicit status capture so `set -e` cannot bypass diagnostics:

```bash
start_rc=0
sudo systemctl start --wait "$unit" || start_rc=$?
result=$(systemctl show "$unit" -p Result --value 2>/dev/null || printf 'unreadable')
main_status=$(systemctl show "$unit" -p ExecMainStatus --value 2>/dev/null || printf 'unreadable')
if [[ "$start_rc" -ne 0 || "$result" != "success" || "$main_status" != "0" ]]; then
  echo "✗ $unit: start_rc=$start_rc Result=$result ExecMainStatus=$main_status"
  journalctl -u "$unit" -n 100 --no-pager
  exit 1
fi
```

Run units sequentially so output identifies the failing target. Query each property separately, with its own label, rather than using one unlabeled multi-property `--value` result. On success, print a concise checkmark and continue.

Do not use `journalctl -f`; it can block after the oneshot completes.

**Verify without starting jobs**:

```bash
just --show backup | grep -E 'list-unit-files|start --wait|Result|journalctl'
```

Expected: all four mechanisms are present.

### Step 3: Update command documentation

Document:

```text
just backup <job>             # run all generated targets for the job
just backup <job> <target>    # run one target
```

Use “job,” not “repo,” because `nori.backups.<job>` is the source declaration and each target yields a separate repository.

Update only active operator docs that contain the old command.

**Verify**:

```bash
rg 'just backup|restic-backups-<repo>' README.md docs/reference/services.md modules/infra/backup/backup.just
```

Expected: examples use the new job/optional-target semantics; no bare generated unit is documented.

### Step 4: Perform one authorized real journey

Ask the operator to choose a small, non-disruptive active backup job and target. Run:

```bash
just backup <job> <target>
```

Expected:

- exact generated unit printed;
- command waits for completion;
- `Result=success` reported;
- a new snapshot is visible through the existing snapshot tooling.

Then, if authorized, run the same job without a target and confirm every declared target runs sequentially. Do not use `media-irreplaceable` for a test unless the operator explicitly accepts the runtime and I/O cost.

### Step 5: Run the static gate

```bash
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- Just parser/dry-run for no target and explicit target.
- Negative runtime calls:
  - unknown job → nonzero with available units;
  - known job + unknown target → nonzero naming exact missing unit.
- Positive operator-approved call against one small job-target unit.
- Optional all-target positive call.

## Done criteria

- [ ] Manual backup resolves generated job-target units.
- [ ] No target means all matching targets; explicit target means exactly one.
- [ ] Zero matches and failed units return nonzero with bounded logs.
- [ ] Recipe waits for the oneshot and never tails indefinitely.
- [ ] Active docs use the new invocation.
- [ ] One operator-approved real backup completes successfully.
- [ ] Full flake check passes.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- the pinned systemd does not support `systemctl start --wait` for these oneshots;
- matching a job name is ambiguous because target names or job names cannot be separated by the final suffix pattern;
- a live verification would run a multi-hour or high-I/O job without explicit approval;
- successful units use a `Result` value other than `success` in the pinned systemd version.

## Maintenance notes

- Generated unit names are the runtime source of truth. Keep the recipe as a resolver rather than duplicating the target registry.
- If a future aggregate systemd target is introduced for other reasons, the recipe may use it only if target-level failure remains visible.
