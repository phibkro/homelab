# Plan 003: Bind `nori.harden` profiles to real systemd units

> **Executor instructions**: Execute test-first. The current configuration contains a real hardening miss, not only a weak test. Run every verification command, keep changes within scope, and stop rather than weakening the invariant to make evaluation pass.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- modules/infra/capabilities/default.nix modules/infra/backup/btrbk-replication.nix modules/infra/backup/btrbk-replica-target.nix modules/infra/backup/restic-target.nix tests/tests.just tests/eval/harden-invariants.nix flake.nix docs/invariants.md`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-rotate-console-credentials.md` (serializes shared `flake.nix` edits)
- **Category**: security, tests
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

`nori.harden` is the repository's default-deny filesystem boundary, but profiles currently create systemd service attributes even when no real executable unit exists. Aurora hardens a phantom `btrbk-replication` unit while the actual `btrbk-family-replica` sender lacks the `/mnt` and `/srv` namespace overlay. The live `test-harden` recipe checks bind paths only, so empty profiles—and therefore most of the security baseline—can pass without a single assertion.

Make invalid unit names fail at eval, fix the current sender, remove non-service placeholders, and make runtime verification observe the baseline properties the abstraction promises.

## Current state

- `modules/infra/capabilities/default.nix:43-45` says each attribute name **must** match a systemd unit.
- The writer at `modules/infra/capabilities/default.nix:107-156` creates `systemd.services.<name>.serviceConfig`, which also makes typo names appear in the module tree.
- The baseline includes `TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ]`, `ProtectHome`, `NoNewPrivileges`, and related properties.
- `modules/infra/backup/btrbk-replication.nix:81-103` creates `btrbk-family-replica`, but line 173 declares `nori.harden.btrbk-replication = { };`.
- Evaluated state at planning time:
  - `btrbk-family-replica.serviceConfig.TemporaryFileSystem` is unset;
  - `btrbk-replication` has the hardening baseline but no `ExecStart`.
- `modules/infra/backup/restic-target.nix:83-89` explicitly says no `restic-target` unit exists, then declares a profile with that name.
- `modules/infra/backup/btrbk-replica-target.nix:21-35` is authorization-only but also declares a non-unit profile.
- `tests/tests.just:421-453` checks only `BindPaths` and `BindReadOnlyPaths`, silently skips missing live units, and never checks `TemporaryFileSystem`, `ProtectHome`, or the universal baseline. At planning time 21 of 46 workstation+aurora profiles had no bind paths, so the recipe performed no substantive assertion for them.

Repository pattern:

- Use module assertions for cross-attribute semantic invariants (`docs/invariants.md:79-92`).
- Test an assertion with one valid and one invalid eval variant, following `tests/eval/route-invariants.nix`.
- Runtime introspection must fail closed when the observed artifact cannot be read.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Targeted eval test | `nix build --no-link .#checks.x86_64-linux.eval-harden-invariants` | exit 0 |
| Inspect sender baseline | `nix eval --json .#nixosConfigurations.aurora.config.systemd.services.btrbk-family-replica.serviceConfig.TemporaryFileSystem` | includes `/mnt:ro` and `/srv:ro` |
| Build affected hosts | `nix build --no-link .#nixosConfigurations.aurora.config.system.build.toplevel .#nixosConfigurations.workstation.config.system.build.toplevel` | exit 0 |
| Runtime test after deploy | `just test-harden` | all declared profiles checked; zero skipped/missing units |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `modules/infra/capabilities/default.nix`
- `modules/infra/backup/btrbk-replication.nix`
- `modules/infra/backup/btrbk-replica-target.nix`
- `modules/infra/backup/restic-target.nix`
- `tests/tests.just`
- `tests/eval/harden-invariants.nix` — create
- `flake.nix`
- `docs/invariants.md` — update enforcement description only

**Out of scope**:

- Hardening every restic or btrbk unit in the repository.
- Adding `ProtectSystem=strict`; it is explicitly deferred at `modules/infra/capabilities/default.nix:125-130`.
- Refactoring the whole backup concern.
- Weakening btrbk's required access to `/mnt/family` merely to satisfy the baseline.
- Changing OpenSSH hardening; `restic-target` is an sshd configuration concern, not its own service.

## Git workflow

- Use the isolated worktree supplied by the dispatcher when applicable.
- Do not push or commit unless authorized.
- Suggested atomic commits if requested:
  1. `test(hardening): reject profiles without executable units`
  2. `fix(backups): harden the real replication sender`
- Keep the tree green after each commit.

## Steps

### Step 1: Write the eval regression test

Create `tests/eval/harden-invariants.nix` using the `mkConfig`/`builtins.tryEval` structure from `tests/eval/route-invariants.nix`.

It must exercise:

1. valid service: a fixture service with `script = "true"` and matching `nori.harden.fixture = { };` evaluates successfully;
2. invalid service: `nori.harden.typo = { };` with no executable service definition fails;
3. valid profile output contains the baseline `TemporaryFileSystem`, `ProtectHome`, and `NoNewPrivileges` values.

Wire it into `flake.nix` as `eval-harden-invariants`.

**Verify RED**:

```bash
nix build --no-link .#checks.x86_64-linux.eval-harden-invariants
```

Expected: fail because the invalid profile currently evaluates.

### Step 2: Add an executable-unit assertion

In `modules/infra/capabilities/default.nix`, add assertions for every `nori.harden` entry. A profile is valid only when the merged service definition has a real executable body, accepted in one of the NixOS forms used by this repository:

- non-empty `systemd.services.<name>.script`; or
- non-empty `systemd.services.<name>.serviceConfig.ExecStart`.

Do not treat the existence of `systemd.services.<name>` as sufficient, because the hardening writer itself creates that attr. The failure message must name the profile and say that its key must match an executable systemd service.

If a legitimate generated service uses a third executable representation, STOP and extend the assertion with a documented, tested representation. Do not add a name allowlist.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.eval-harden-invariants
```

Expected: the fixture test passes. Then force production assertions explicitly:

```bash
nix eval --raw .#nixosConfigurations.aurora.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.workstation.config.system.build.toplevel.drvPath
```

Expected intermediate RED state: Aurora fails and names `btrbk-replication` and `restic-target`; workstation fails and names `btrbk-replica-target`. Do not proceed unless those production failures are observed and no additional unexpected profile appears.

### Step 3: Fix the real btrbk sender and remove non-service profiles

- In `btrbk-replication.nix`, replace the phantom key with the actual unit:

```nix
nori.harden.btrbk-family-replica.binds = [ "/mnt/family" ];
```

Btrbk creates snapshots under `/mnt/family/.snapshots`, so this access must be writable. Do not use `readOnlyBinds`.

- Remove `nori.harden.btrbk-replica-target`; the module only adds an authorized key to the existing btrbk user and owns no unit.
- Remove `nori.harden.restic-target`; its own comment correctly says the behavior lives in sshd.
- Keep explicit backup intents and comments explaining why these modules have no standalone hardening profile.

**Verify**:

```bash
nix eval --json \
  .#nixosConfigurations.aurora.config.systemd.services.btrbk-family-replica.serviceConfig.TemporaryFileSystem
nix eval --json \
  .#nixosConfigurations.aurora.config.systemd.services.btrbk-family-replica.serviceConfig.BindPaths
```

Expected: the first includes `/mnt:ro` and `/srv:ro`; the second includes `/mnt/family`.

Also verify no empty backup-infra profiles remain:

```bash
for h in workstation aurora; do
  nix eval --json ".#nixosConfigurations.$h.config.nori.harden" --apply builtins.attrNames
done
```

Expected: no `btrbk-replication`, `btrbk-replica-target`, or `restic-target` key.

### Step 4: Make `test-harden` inspect the promised baseline

Update `tests/tests.just` so every declared profile:

1. fails if `systemctl cat <unit>.service` fails;
2. fails if live `ExecStart` is empty;
3. verifies `/mnt:ro` and `/srv:ro` in `TemporaryFileSystem`;
4. verifies `NoNewPrivileges=yes`;
5. verifies `ProtectHome` against the evaluated profile when `protectHome != null`;
6. retains exact bind and read-only-bind verification;
7. reports profiles checked, not “skipped units.” Missing observation is failure.

Use `systemctl show` properties, not text parsing of `systemctl cat`, for effective values.

**Verify**:

```bash
just --list | grep test-harden
bash -n <(just --show test-harden)
```

Expected: recipe exists and generated shell parses. After deployment, `just test-harden` must report zero missing units.

### Step 5: Update the invariant documentation and run gates

Update `docs/invariants.md` so the hardening claim names both enforcement mechanisms:

- source coverage flake check (`every-service-has-fs-hardening`);
- eval assertion that profile keys identify executable units;
- runtime baseline verification (`just test-harden`).

Do not copy a current service list into prose.

**Verify**:

```bash
nix build --no-link \
  .#nixosConfigurations.aurora.config.system.build.toplevel \
  .#nixosConfigurations.workstation.config.system.build.toplevel
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- Layer 1: `eval-harden-invariants` with valid profile, phantom profile, and baseline-output assertions.
- Layer 3: strengthened `just test-harden` against effective systemd properties.
- Real deployment check on aurora:
  - `systemctl show btrbk-family-replica.service -p TemporaryFileSystem -p BindPaths -p NoNewPrivileges -p ProtectHome` matches declaration;
  - start the unit only if operator authorizes an out-of-cycle replication run; otherwise wait for the scheduled run and inspect its result.

## Done criteria

- [ ] Phantom hardening profiles fail eval.
- [ ] The real `btrbk-family-replica` unit carries the baseline and writable `/mnt/family` bind.
- [ ] Non-service modules no longer claim standalone hardening profiles.
- [ ] `test-harden` checks baseline properties for every profile and fails on unreadable/missing units.
- [ ] Targeted eval test, both host builds, and full flake check pass.
- [ ] Live aurora systemd properties match after deployment.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- a legitimate hardened service has neither a non-empty `script` nor `ExecStart`;
- hardening the actual btrbk sender prevents required snapshot creation despite `/mnt/family` being writable-bound;
- fixing the issue requires weakening the universal baseline;
- runtime systemd property names differ from those documented here;
- another phantom profile appears outside the three known modules. Report it and extend scope only with operator approval.

## Maintenance notes

- The eval assertion makes the bad state unrepresentable; `test-harden` then verifies deployment rather than compensating for a weak model.
- Any new service representation added by NixOS must be reflected in both the assertion and its negative test.
- Reviewers should scrutinize writable binds on backup tools: grant the smallest subtree that still permits snapshot creation.
