# Plan 009: Claim music files atomically before publishing and deleting them

> **Executor instructions**: This script moves irreplaceable media. Work test-first against `/tmp`; never test a race by manipulating `/mnt/media`. Preserve crash recovery: after any interruption, the only copy must remain discoverable for a later run.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- modules/services/music-ingest.nix modules/services/music-ingest.sh modules/services/music-ingest.test.sh modules/machines/workstation/default.nix docs/runbooks/music-flac-ingest.md flake.nix`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/006-fail-closed-backup-runtime-tests.md` (serializes shared `flake.nix` edits)
- **Category**: bug
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

The ingest script checks mtime and Syncthing temporary siblings once, copies the source, publishes the copy, and then deletes the staging path. Syncthing may atomically replace or resume a file after that first check. The script can therefore publish bytes from one version and delete another version from staging.

Make ownership explicit: atomically rename an eligible source out of the Syncthing-managed folder into a durable inflight directory on the same filesystem, then copy from that claimed path. New remote writes remain at the original path for the next sweep, while crashes leave a recoverable inflight copy.

## Current state

- `modules/services/music-ingest.sh:98-108` checks temporary sibling and age before copying.
- `modules/services/music-ingest.sh:135-151` copies, fsyncs, renames into the master, then removes the original staging path without revalidating ownership.
- `modules/services/music-ingest.test.sh` covers stable/fresh files, temp siblings, dedupe, conflicts, permissions, art, and rerun idempotence, but not replacement during ingest or crash recovery.
- Workstation config:
  - staging: `/mnt/media/staging/music-flac` (`modules/machines/workstation/default.nix:169-180`);
  - master: `/mnt/media/library/music`;
  - both are on the same `/mnt/media` filesystem.
- The runbook says the crash-safe path is `copy → fsync → rename → unlink` (`docs/runbooks/music-flac-ingest.md:42-45`), but it does not model source ownership.

Target flow:

```text
Syncthing source
   └─ atomic rename on same filesystem
        → inflight/<relative-path>      # durable ownership claim
             └─ copy + verify + fsync
                  → atomic master rename
                       └─ remove inflight claim

If Syncthing writes the original path again, that new file remains for next run.
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Fixture | `nix shell nixpkgs#b3sum --command bash modules/services/music-ingest.test.sh` | all cases pass |
| Shell check/build | `nix build --no-link .#nixosConfigurations.workstation.config.system.build.toplevel` | exit 0; writeShellApplication shellcheck passes |
| Focused CI check | `nix build --no-link .#checks.x86_64-linux.music-ingest-fixture` | exit 0 |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `modules/services/music-ingest.nix`
- `modules/services/music-ingest.sh`
- `modules/services/music-ingest.test.sh`
- `modules/machines/workstation/default.nix`
- `docs/runbooks/music-flac-ingest.md`
- `flake.nix`

**Out of scope**:

- Syncthing folder membership or device configuration.
- Moving the master library to another host.
- Changing supported media extensions, dedupe policy, conflict semantics, or FLAC-to-Opus behavior.
- Running the fixture against real media.
- Silently deleting orphaned inflight files.

## Git workflow

- Use an isolated worktree.
- Do not start the live ingest service without operator approval.
- Suggested commits:
  1. `test(music-ingest): cover inflight recovery and replacement`
  2. `fix(music-ingest): claim sources before publish`

## Steps

### Step 1: Extend the option model with an explicit inflight path

Add `nori.musicIngest.inflightPath` as a required string when enabled; do not guess a global default. Configure workstation with:

```nix
inflightPath = "/mnt/media/staging/.music-ingest-inflight";
```

This path is a sibling of the Syncthing-managed `music-flac` folder, not inside it, and remains on the same filesystem.

Add assertions:

- inflight is not inside `stagingPath`;
- inflight is not inside the master music path;
- staging, inflight, and master are distinct lexical paths.

Create the inflight directory through tmpfiles with `music-ingest:media` ownership and mode `2770`. Add it to `nori.harden.music-ingest.binds` and pass it as `MUSIC_INGEST_INFLIGHT`.

**Verify**:

```bash
nix eval --raw .#nixosConfigurations.workstation.config.nori.musicIngest.inflightPath
```

Expected: `/mnt/media/staging/.music-ingest-inflight`.

### Step 2: Write the race and recovery tests first

Extend `music-ingest.test.sh` with:

1. **Recovered claim**: pre-populate `inflight/Artist/Album/file.flac`; run the script; file lands in master and disappears from inflight.
2. **New version after claim**: pre-populate an inflight claim and a different file at the original staging path. The claim is published; the new staging file remains for a later stability window and is not deleted.
3. **Conflict from inflight**: claimed content colliding with different master content moves to the existing conflict quarantine without touching master.
4. **Interrupted publish**: create a fixture-local fake `cp` executable earlier in `PATH`. It must return nonzero only when copying the named sentinel file and delegate every other invocation to the real absolute `cp` path captured before the shim is installed. Run the production script with that PATH, assert nonzero exit and the claimed file still present, remove the shim, rerun, and assert recovery succeeds. Do not add a test-only branch or environment hook to the production script.
5. **Cross-device guard**: configure inflight on a different filesystem in the fixture when feasible; script fails before moving any data.

The test must use only its `/tmp` tree. When a normal staging source and an existing inflight claim have the same relative path, the deterministic rule is: leave both untouched, print a collision error, mark the run failed, and require operator/recovery handling. Never overwrite either copy.

**Verify RED**:

```bash
nix shell nixpkgs#b3sum --command bash modules/services/music-ingest.test.sh
```

Expected before implementation: new cases fail.

### Step 3: Claim eligible files atomically

Refactor the script into two phases/functions:

1. `process_claim <claimed-path> <relative-path>` — owns dedupe, conflict, copy, checksum, fsync, publish, and claim removal.
2. normal staging scan — after current stability guards:
   - create the claim parent under inflight;
   - atomically `mv` the source to the claim path;
   - if the source disappeared before the rename, leave state untouched and continue as an unstable candidate;
   - if the claim already exists, leave both paths untouched, print both paths, set the run failure flag, and continue collecting other work;
   - call `process_claim`.

Before processing anything, compare `stat -c %d` device IDs for staging and inflight. They must match so the ownership claim is atomic. Also verify master and its temporary file directory are on the expected filesystem for atomic final rename.

Process pre-existing inflight claims **before** normal staging files on every run. This is crash recovery, not cleanup.

After copying claim to the master temp file, compare the temp file's BLAKE3 digest with the claimed source before publishing. If they differ, remove only the temp file, retain the claim, and fail.

Never remove the original staging path after claiming; it may now contain a newer Syncthing version. Remove only the owned inflight claim after durable master publication.

### Step 4: Preserve dedupe and conflict semantics under ownership

- Identical destination: remove the claim, not the current staging path.
- Different destination: move the claim to `<staging>/.conflicts/<relative-path>`; preserve master.
- If a conflict file already exists, do not overwrite it; add a deterministic unique suffix or fail while retaining the claim.
- Ensure `trap` removes only temporary master files. It must never delete claims.

**Verify GREEN**:

```bash
nix shell nixpkgs#b3sum --command bash modules/services/music-ingest.test.sh
```

Expected: all old and new cases pass.

### Step 5: Wire the fixture into the flake gate

Add `music-ingest-fixture` in `flake.nix`. Provide `bash`, `b3sum`, `coreutils`, and `findutils`, run the same committed fixture script, and touch `$out` on success.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.music-ingest-fixture
nix build --no-link .#nixosConfigurations.workstation.config.system.build.toplevel
```

Expected: both exit 0.

### Step 6: Update the runbook and perform a contained live check

Update the flow diagram and crash-safety explanation in `docs/runbooks/music-flac-ingest.md`. Name the inflight directory and recovery behavior. State that it is outside the Syncthing folder and must share a filesystem with staging.

After deployment and operator approval:

1. ensure normal staging is quiet;
2. place a disposable, non-personal fixture file in staging;
3. start `music-ingest.service`;
4. verify no inflight files remain and the fixture lands correctly;
5. remove the disposable master fixture.

Do not use a real unique recording as the first live test.

## Test plan

- Existing behavior cases remain.
- New ownership cases: recovered claim, concurrent new original, conflict, interrupted publish, cross-device rejection.
- CI executes the actual production script artifact.
- Workstation closure build shellchecks the script.
- One disposable live fixture after deployment.

## Done criteria

- [ ] Eligible sources are atomically moved out of the Syncthing folder before copying.
- [ ] Every inflight claim is recoverable on the next run.
- [ ] A new original path created after claim is never deleted by the current run.
- [ ] Claimed and copied bytes are checksum-equal before publish.
- [ ] Fixture is part of `nix flake check` and all cases pass.
- [ ] Workstation build and full gate pass.
- [ ] Runbook matches the ownership model.
- [ ] Contained live fixture succeeds.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- staging and the chosen inflight directory are on different filesystems;
- the runtime Syncthing folder includes the proposed inflight path;
- a crash-recovery design would leave the only copy hidden and undiscoverable;
- tests require touching `/mnt/media`;
- conflict handling would overwrite an existing quarantined file;
- implementation requires changing master-sync topology.

## Maintenance notes

- Inflight is durable state until publish succeeds; never treat it as disposable temp data.
- Ownership claims solve the check-then-act race. Do not regress to “check mtime, then later delete path.”
- Reviewers should follow each deletion and verify the script owns the exact inode/path being removed.
