# Plan 013: Repair active documentation and enforce its routing paths

> **Executor instructions**: Update active guidance only. Historical ADRs, plans, specs, and reports may intentionally retain old names when describing the past; do not bulk-replace them. Extend mechanical routing checks before correcting prose so future drift fails CI.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- README.md docs/README.md docs/reference/module-authoring.md docs/reference/runtime-tests.md modules/machines/aurora/default.nix modules/services/immich.nix modules/services/miniflux.nix lint/checks/routing-coherence.sh docs/invariants.md`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: `plans/007-resolve-manual-backup-units.md`, `plans/012-verify-authelia-client-registry.md` (serializes `README.md` and runtime-test docs)
- **Category**: docs, dx
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

The repository treats documentation as the onboarding medium for amnesiac agents, but several active entry points still describe the pre-restructure tree, missing uppercase files, Aurora's retired role, and the old `*.nori.lan` domain. These are operational instructions, not harmless history: they send implementers to nonexistent modules and operators to obsolete URLs.

Correct active guidance and extend `routing-coherence` so both root and `docs/` routing tables must point to real files. Preserve historical language only in dated decision/history artifacts.

## Current state

- `docs/README.md:20-56` routes to nonexistent uppercase root files (`GLOSSARY.md`, `TOPOLOGY.md`, etc.), removed files (`SKILL_INDEX.md`, `PROJECTS.md`), and old `superpowers/` paths.
- Root `README.md:86-120` still shows `modules/effects/` and top-level `home/`, while current code is `modules/infra/` and `modules/home/`.
- `docs/reference/module-authoring.md:107-110` describes an `effects/` concern; line 145 refers to `server/`; lines 327-341 describe obsolete recipe signatures and deployment behavior.
- `docs/reference/runtime-tests.md:58-66` names obsolete files such as `harden.nix`, `fs.nix`, and `rust-motd.nix` and still discusses `effects/`.
- `modules/machines/aurora/default.nix:9-31` says Aurora is a single-role Immich ML offload and authoritative state remains on workstation; lines 75-82 say family services are still standing up empty. The same file enables the full family-vault workload at lines 91-113.
- `modules/services/immich.nix:27-38` and `modules/services/miniflux.nix:46-47` give active setup instructions with `*.nori.lan`; canonical access is `*.home.phibkro.org` through `config.nori.domain`.
- `flake.nix:763-782` runs `lint/checks/routing-coherence.sh`, but the check currently protects the root `CLAUDE.md` routing map, not the `docs/README.md` mirror.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Routing check | `bash lint/checks/routing-coherence.sh .` | exit 0 |
| Migration path check | `just check-migration` | exit 0 |
| Search active drift | `rg 'GLOSSARY\.md|TOPOLOGY\.md|modules/effects|server/|\.nori\.lan' README.md docs/README.md docs/reference modules/machines/aurora modules/services/{immich,miniflux}.nix` | no unintended active references |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `README.md`
- `docs/README.md`
- `docs/reference/module-authoring.md`
- `docs/reference/runtime-tests.md`
- `modules/machines/aurora/default.nix` — comments only
- `modules/services/immich.nix` — comments/instructions only
- `modules/services/miniflux.nix` — comments/instructions only
- `lint/checks/routing-coherence.sh`
- `docs/invariants.md` — routing-check coverage description only

**Out of scope**:

- Historical files under `docs/decisions/`, `docs/plans/`, `docs/reports/`, or dated `docs/specs/` unless an active entry point links to a nonexistent path.
- Changing executable Nix behavior, service placement, routes, or domains.
- Rewriting all documentation for tone.
- Generating a new documentation framework.

## Git workflow

- Use an isolated worktree.
- Keep code changes limited to the routing check; all module changes are comments only.
- Suggested commit: `docs: repair active routing and post-migration guidance`.

## Steps

### Step 1: Extend routing coherence to `docs/README.md`

Read `lint/checks/routing-coherence.sh` fully before editing. Add validation for every path in the two routing tables in `docs/README.md`:

- mandatory docs table;
- topic-triggered reference table;
- drill-down table.

The check must understand backtick-enclosed relative paths and directory entries. It must fail with table line number and missing destination. Do not scan arbitrary prose examples; scope parsing to table rows so illustrative snippets do not produce false positives.

Also assert that the mandatory `docs/README.md` entries match the root `CLAUDE.md` mandatory pair by resolved path. Avoid copying the full table into the script; derive table cells from the files.

**Verify RED**:

```bash
bash lint/checks/routing-coherence.sh .
```

Expected before docs correction: failure listing current missing paths.

### Step 2: Replace `docs/README.md` with the current routing map

Make it mirror the current root `CLAUDE.md` docs map:

- lowercase `docs/glossary.md`, `docs/invariants.md`, `docs/roadmap.md`;
- `docs/reference/<topic>.md` paths;
- generated docs entries where relevant;
- current drill-down directories (`decisions`, `runbooks`, `plans`, `specs`, `reports`, `installs`);
- `.claude/skills/gotcha-*/` for procedures.

Because the file is already inside `docs/`, choose and apply one consistent relative-path convention; the routing check must resolve it accordingly.

Remove the instruction that top-level references use uppercase filenames.

**Verify**:

```bash
bash lint/checks/routing-coherence.sh .
```

Expected: docs routing portion passes.

### Step 3: Correct repository shape and authoring guidance

Update root `README.md` and `docs/reference/module-authoring.md` to current code:

- `modules/infra/` for platform concerns;
- `modules/home/` for home-manager modules;
- folders under `modules/services/` signal coupling;
- no `server/` or `effects/` tree;
- current `Justfile` local-by-default semantics and recipe signatures;
- current service examples (`include`, not obsolete field names if any drifted).

Use the actual tree and `Justfile` as source. Do not preserve obsolete paths as transitional aliases unless code still supports them.

**Verify**:

```bash
just check-migration
rg 'modules/effects|server/' README.md docs/reference/module-authoring.md docs/reference/runtime-tests.md
```

Expected: migration check passes; search returns no active obsolete architecture references.

### Step 4: Correct runtime-test inventory and semantics

Update `docs/reference/runtime-tests.md` to current paths:

- `modules/infra/capabilities/default.nix` for `nori.harden`;
- `modules/infra/storage/default.nix` for `nori.fs`;
- `modules/infra/motd.nix` rather than `rust-motd.nix`;
- `modules/infra/`, not `effects/`;
- current shipped recipes, including `test-harden` and `test-fs`.

Do not maintain a static list if the live `just --list` or generated check is a better oracle. Where possible, link to `just --list` or the `infra-concerns-have-tests` mapping instead of copying names.

### Step 5: Refresh Aurora and service comments

Rewrite Aurora's file header and service-placement comment to describe current truth:

- always-on family vault;
- `/mnt/family/*` authoritative data;
- family-tier service backends;
- OneTouch target;
- btrbk source to workstation;
- no entry-plane role (pi owns it).

Remove “standing up empty” and workstation-authoritative migration instructions.

In Immich and Miniflux setup comments, replace literal `*.nori.lan` examples with `${config.nori.domain}`-based canonical examples in prose, e.g. `https://photos.<nori.domain>`. Do not alter transitional redirect implementation elsewhere.

**Verify**:

```bash
rg '\.nori\.lan|standing up empty|single-role' \
  modules/machines/aurora/default.nix \
  modules/services/immich.nix \
  modules/services/miniflux.nix
```

Expected: no obsolete active instructions. Legitimate historical references, if any, must be explicitly labeled historical.

### Step 6: Update invariant coverage and run gates

Update `docs/invariants.md` to say `routing-coherence` validates both routing entry points. Do not add a hand-maintained destination inventory.

Run:

```bash
bash lint/checks/routing-coherence.sh .
just check-migration
nix flake check --print-build-logs
```

Expected: all exit 0.

## Test plan

- Routing check fails on one deliberately broken `docs/README.md` path; revert.
- Routing check fails when a mandatory doc differs between root and docs entry points; revert.
- Migration path-coherence check passes.
- Search active files for obsolete architecture/domain tokens.
- Full flake check passes.

## Done criteria

- [ ] Every `docs/README.md` route resolves.
- [ ] Root and docs mandatory routing entries agree mechanically.
- [ ] Active architecture docs use `modules/infra`, `modules/home`, and `modules/services` correctly.
- [ ] Aurora comments match its family-vault role.
- [ ] Active setup instructions use the canonical domain abstraction.
- [ ] Historical artifacts were not bulk-rewritten.
- [ ] Routing, migration, and full flake checks pass.
- [ ] No executable service behavior changed.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- an apparently obsolete path is still consumed by code or generated docs;
- routing-table parsing requires a fragile general Markdown parser rather than scoped table extraction;
- correcting prose reveals code behavior that actually contradicts the accepted ADRs;
- a historical file must change to make an active check pass without being mislabeled as active guidance;
- comments cannot be corrected without changing configuration.

## Maintenance notes

- Active docs describe current behavior; dated decisions describe history. Keep that boundary sharp.
- The routing check, not reviewer memory, owns path existence.
- Avoid restoring mirrored static inventories when a live oracle exists.
