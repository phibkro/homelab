# Plan 012: Compare live Authelia clients with declared OIDC routes

> **Executor instructions**: Compare identities, not only counts. Read the active process's actual config arguments so the test observes the deployed generation rather than the working tree twice. Never print client secrets or rendered secret values.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- tests/tests.just tests/runtime/assertions.sh tests/runtime/assertions.test.sh modules/infra/access/authelia.nix docs/reference/runtime-tests.md`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/006-fail-closed-backup-runtime-tests.md`, `plans/010-fail-closed-observability.md` (serializes shared runtime helpers and `tests/tests.just`)
- **Category**: tests
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

`test-authelia` documents a route-to-client registry comparison but currently checks only that each route's two secret files exist. A generator regression or stale deployed Authelia config can omit or retain a client while every secret file remains present. Family login then fails despite a green test.

Compare the declared client IDs from `nori.lanRoutes` with the IDs in the active Authelia process's rendered configuration. Set equality catches missing and unexpected clients; count equality alone does not.

## Current state

- `tests/tests.just:189-202` says Tier 4 compares Authelia client count with OIDC route declarations.
- `tests/tests.just:254-270` actually loops over secret files only.
- `modules/infra/access/authelia.nix:179-188` generates `identity_providers.oidc.clients` from route declarations.
- The active service ExecStart at planning time used:

```text
authelia --config <config.yml>,<oidc-jwks.yaml>
```

- Planning-time evaluated client IDs were `audio`, `metrics`, `news`, `photos`, `requests`, and `vault`. Do not hard-code this list; derive both sides.
- Plan 006 creates `tests/runtime/assertions.sh`; extend that shared helper for set comparison rather than embedding another ad-hoc implementation.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Helper tests | `bash tests/runtime/assertions.test.sh` | set cases pass |
| Pi build | `nix build --no-link .#nixosConfigurations.pi.config.system.build.toplevel` | exit 0 |
| Runtime test | `just test-authelia` | declared and live client sets equal |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `tests/tests.just`
- `tests/runtime/assertions.sh`
- `tests/runtime/assertions.test.sh`
- `modules/infra/access/authelia.nix` — comments only if needed
- `docs/reference/runtime-tests.md`

**Out of scope**:

- Changing OIDC clients, secrets, hashes, redirect URIs, or Authelia storage.
- Adding an unsupported Authelia admin API.
- Reading or printing client secrets.
- Replacing the real config comparison with the same working-tree Nix eval on both sides.
- Optimizing tool startup; Plan 014 handles the common runtime environment.

## Git workflow

- Use an isolated worktree.
- Do not deploy or restart Authelia without operator approval.
- Suggested commit: `test(authelia): compare live and declared oidc clients`.

## Steps

### Step 1: Add a tested line-set equality helper

Extend `tests/runtime/assertions.sh` with a function that compares newline-delimited sets after removing empty lines and sorting uniquely. It must report:

- values missing from actual;
- unexpected values present in actual.

Do not compare only counts.

Extend `assertions.test.sh` with:

- equal sets in different order pass;
- duplicate lines do not affect equality;
- same count but different values fails;
- missing value fails;
- unexpected value fails;
- empty/empty passes only when the caller explicitly allows it. `test-authelia` must require a non-empty declared set.

**Verify**:

```bash
bash tests/runtime/assertions.test.sh
```

Expected: all cases pass.

### Step 2: Derive the declared client set

In `test-authelia`, source the shared helper through `repo_root=$(git rev-parse --show-toplevel)` exactly as specified in Plan 006. Evaluate the current host's `nori.lanRoutes` and emit route names where `.oidc != null`. Sort uniquely. Require at least one declared OIDC route; an empty set on this homelab is a failure because Authelia is the family identity provider.

Retain the existing per-route secret-file checks as a separate tier. Rename the tiers so comments and implementation match.

**Verify source shape**:

```bash
just --show test-authelia | grep -E 'declared.*oidc|secret|client set'
```

Expected: declarations, secrets, and client registry are distinct checks.

### Step 3: Read the active process's actual config files

On pi, obtain `MainPID` for `authelia-main.service`, then read `/proc/<pid>/cmdline` as NUL-separated arguments. Locate the argument following `--config` and split its comma-separated paths.

This is the deployed process's actual configuration, not a guessed path. Fail if:

- service has no live PID;
- `--config` is absent;
- a config path is unreadable;
- no OIDC client IDs can be parsed.

Use `pkgs.yq-go` from the pinned nixpkgs input; its executable is `yq`. For each comma-separated config path, run exactly:

```bash
nix shell nixpkgs#yq-go -c yq -r \
  '.identity_providers.oidc.clients[]?.client_id // empty' "$config_path"
```

Run that command on pi through the existing local/SSH helper and capture only stdout client IDs. Redirect parser diagnostics separately; never print the full YAML or any other field. Plan 014 must later put `pkgs.yq-go` in the shared runtime environment and replace this one-shot shell without changing the expression.

If the active config uses template syntax that the YAML parser cannot read, use Authelia's supported config export/validation command only if it can emit client IDs without secrets. Otherwise STOP; do not regex arbitrary YAML.

### Step 4: Compare exact client identities

Invoke the shared set-equality helper with declared route names and live client IDs. Print only IDs in missing/unexpected diagnostics.

Expected healthy output:

```text
✓ live Authelia OIDC clients exactly match declared OIDC routes
```

**Verify after deployment**:

```bash
just test-authelia
```

Expected: service, health, discovery, secret files, and exact client set all pass.

### Step 5: Prove mismatch detection without touching production

Add a fixture case to `assertions.test.sh` where declared and actual sets have equal counts but different IDs; it must fail.

For an integration-level negative test, use an isolated NixOS test config or a temporary local copy of parsed ID files. Do not edit production route declarations or live Authelia config merely to force a mismatch.

### Step 6: Update docs and gates

Update `docs/reference/runtime-tests.md` so `test-authelia` explicitly promises exact set equality and deployed-process config observation.

Run:

```bash
bash tests/runtime/assertions.test.sh
nix build --no-link .#nixosConfigurations.pi.config.system.build.toplevel
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- Pure set helper tests, including equal-count/different-value failure.
- Runtime positive path against active pi Authelia.
- Failure paths: no PID, no config argument, unreadable config, empty clients, missing client, unexpected client.
- Existing secret-file and OIDC-discovery checks remain.

## Done criteria

- [ ] The recipe's comments and tiers match implementation.
- [ ] Declared OIDC routes are non-empty and derived dynamically.
- [ ] Live client IDs come from the active process's real config arguments.
- [ ] Exact set equality is checked; missing and unexpected IDs are named.
- [ ] No secret values or full rendered configs are printed.
- [ ] Helper tests, Pi build, runtime test, and full gate pass.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- Plan 006 has not created the shared runtime assertion helper;
- `pkgs.yq-go` cannot parse the active config with the exact client-ID-only expression without exposing other fields;
- Authelia loads clients from a runtime source not represented by the `--config` files;
- reading `/proc/<pid>/cmdline` requires broadening permissions;
- a real mismatch is found. Report it before changing client declarations.

## Maintenance notes

- Compare identities, not cardinality.
- The working tree is intent; the active process arguments are deployed reality. Keep those two evidence sources independent.
- Plan 014 may change how the YAML parser is supplied but must preserve this observation path.
