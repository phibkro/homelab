# Plan 006: Make backup runtime checks fail closed

> **Executor instructions**: Preserve the distinction between an intentionally skipped backup declaration and an active repository that has never produced a snapshot. Add tests for the pure path and empty-value logic before changing the live recipes.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- tests/tests.just tests/runtime/assertions.sh tests/runtime/assertions.test.sh flake.nix docs/reference/runtime-tests.md`

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: `plans/005-place-replica-intent-on-target.md` (serializes shared `flake.nix` edits)
- **Category**: bug, tests
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

`just test-backups` claims that every active repository has a fresh snapshot, but an empty snapshot result currently prints “no snapshots yet” and continues successfully. `just test-fs` also treats raw string prefixes as containment, so `/mnt/family/foo` can incorrectly cover `/mnt/family/foobar`. Both failures produce green output for unprotected data.

Move the reusable pure predicates into a tested helper and make uncertainty fail closed.

## Current state

```bash
# tests/tests.just:332-335
latest=$(snapshot_age "$repo" "$mount")
if [[ -z "$latest" ]]; then
  echo "  · $repo/$target: no snapshots yet"; continue
fi
```

```bash
# tests/tests.just:501-504
[[ -n "$cov" ]] && [[ "$path" == "$cov"* ]] && exit 100
```

- Active-vs-skipped intent is already structural in `nori.backups`: active entries have `include`, skipped entries have a reason.
- The runtime recipe discovers generated `restic-backups-*.service` units, so every looped repository is active and must have at least one snapshot.
- Runtime tests belong under `tests/tests.just`; pure shell behavior may be extracted to a small sourceable helper so CI can test it without a live restic repository.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Pure helper tests | `bash tests/runtime/assertions.test.sh` | all named cases pass |
| Targeted flake check | `nix build --no-link .#checks.x86_64-linux.runtime-assertion-tests` | exit 0 |
| Parse recipes | `just --summary` | exit 0 |
| Live verification | `just test-backups && just test-fs` | all active repos fresh; irreplaceable paths covered |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `tests/tests.just`
- `tests/runtime/assertions.sh` — create
- `tests/runtime/assertions.test.sh` — create
- `flake.nix`
- `docs/reference/runtime-tests.md`

**Out of scope**:

- Changing backup schedules, repositories, retention, credentials, or include paths.
- Triggering backups automatically to make a red test green.
- Treating a skipped backup intent as active.
- Refactoring every runtime recipe into standalone scripts; Plan 014 handles process-start overhead.

## Git workflow

- Use the isolated worktree supplied by the dispatcher.
- Do not deploy or trigger a backup without operator approval.
- Suggested commit: `fix(tests): fail closed on missing backup evidence`.

## Steps

### Step 1: Extract and test path-boundary logic

Create `tests/runtime/assertions.sh` with a sourceable function:

```bash
path_covers() {
  local cover=$1 path=$2
  [[ "$path" == "$cover" || "$path" == "$cover/"* ]]
}
```

Normalize only trailing slashes needed for this repository's absolute Nix paths. Do not call `realpath`: paths may be declared before mounts are present, and runtime namespace views can differ.

Create `tests/runtime/assertions.test.sh` covering:

- exact path covers itself;
- parent covers child;
- `/foo` does not cover `/foobar`;
- `/foo/bar` does not cover `/foo/barley`;
- trailing slash normalization;
- empty cover never matches.

The test must print a useful case name and exit nonzero on the first or accumulated failure.

**Verify RED/GREEN**:

```bash
bash tests/runtime/assertions.test.sh
```

Expected after implementation: exit 0 with all cases shown as passing.

### Step 2: Use the helper in `test-fs`

Source the helper at the beginning of `test-fs` with this exact repo-root-independent pattern:

```bash
repo_root=$(git rev-parse --show-toplevel)
# shellcheck source=tests/runtime/assertions.sh
source "$repo_root/tests/runtime/assertions.sh"
```

Fail if `git rev-parse` or `source` fails. Replace the `[[ "$path" == "$cov"* ]]` loop with `path_covers "$cov" "$path"`.

Keep exact-match behavior. Do not silently normalize relative paths; every `nori.fs` and backup include involved here should be absolute.

**Verify**:

```bash
just --show test-fs | grep path_covers
```

Expected: the recipe sources and invokes the shared helper; the raw prefix expression is gone.

### Step 3: Make a missing snapshot a hard failure

In `test-backups`, change the empty `latest` branch to:

- print `✗ <repo>/<target>: repository has no snapshots`;
- set `fail=1`;
- continue only to collect all failures.

Also count checked `(repo,target)` pairs and fail if zero pairs were checked. Keep shell-pipeline errors explicit: capture `systemctl` output first and emit a clear “no generated backup units found” failure rather than relying on `set -e` to terminate in a command substitution.

Do not add a grace-period exception. A new active backup is not verified until its first manual or scheduled snapshot exists; the correct operational response is to run and validate it, not declare green early.

**Verify source shape**:

```bash
just --show test-backups | grep -E 'no snapshots|pairs_checked|no generated backup'
```

Expected: all three failure paths are present.

### Step 4: Wire the helper tests into CI

Add `runtime-assertion-tests` to `flake.nix` using `runCommandLocal` with Bash. It must run `tests/runtime/assertions.test.sh` from the repository source and create `$out` only on success.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.runtime-assertion-tests
```

Expected: exit 0. Temporarily reverse the sibling-boundary assertion and confirm the check fails; revert immediately.

### Step 5: Run live checks without repairing evidence silently

Run:

```bash
just test-backups
just test-fs
```

If either now exposes a repository with no snapshots or an irreplaceable sibling-path false positive, report the exact job/path. Do not trigger a backup or change declarations without operator approval; that is operational remediation outside this code fix.

Update `docs/reference/runtime-tests.md` to state:

- active repository with zero snapshots is failure;
- coverage means exact path or descendant at a `/` boundary;
- empty observed registries fail rather than skip.

**Verify**:

```bash
nix flake check --print-build-logs
```

Expected: exit 0 after any separately authorized live-state remediation.

## Test plan

- Pure shell tests for path containment and empty values.
- Static recipe inspection proving the helper is used.
- Live `test-backups` and `test-fs` against current declarations.
- Negative mutation: `/foo` must not cover `/foobar`.
- Negative live fixture, if safely available: a temporary generated backup unit with no repository snapshot must make `test-backups` fail. Do not alter production repositories solely for this test.

## Done criteria

- [ ] No-snapshot active repositories fail `test-backups`.
- [ ] Zero checked backup pairs fail explicitly.
- [ ] Path coverage uses exact-or-`/`-descendant semantics.
- [ ] Shared helper tests are wired into `nix flake check`.
- [ ] Live backup and fs tests pass or any pre-existing red state is reported without concealment.
- [ ] Documentation matches fail-closed behavior.
- [ ] Full flake check passes.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- live tests reveal an actual missing backup or uncovered irreplaceable path; report it before changing backup declarations or running jobs;
- a declared path contains non-normalized `..` components or relative paths;
- sourcing the helper requires dependence on the caller's current directory;
- the implementation adds a bootstrap grace period to suppress a real missing snapshot.

## Maintenance notes

- Keep pure runtime-test predicates in `tests/runtime/assertions.sh`; do not duplicate them back into recipes.
- A runtime test that cannot observe evidence must fail. “Skipped” is only valid when the declaration itself says the concern is intentionally absent.
