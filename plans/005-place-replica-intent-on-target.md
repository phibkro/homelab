# Plan 005: Make replica intent identical on source and target hosts

> **Executor instructions**: Treat `nori.replicas` as the single source of truth for both sending and verification. Do not fix this by duplicating declarations in aurora and workstation host files. Run the negative and positive eval tests before building host closures.
>
> **Drift check (run first)**:
> `git diff --stat 0cef85b..HEAD -- modules/infra/backup/btrbk-replication.nix modules/infra/storage/replication.nix tests/eval/replica-placement.nix flake.nix docs/reference/storage.md docs/generated/replicas.md`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/004-authenticate-suwayomi-api.md` (serializes shared `flake.nix` edits)
- **Category**: bug
- **Planned at**: commit `0cef85b`, 2026-07-14

## Why this matters

Aurora currently declares five `nori.replicas` entries inside an Aurora-only gate, while verifier units are generated from the target host's local registry. Workstation therefore evaluates an empty registry and emits no verifier units. A stalled or missing family-data receive is invisible despite comments and runtime tests claiming otherwise.

The registry must be host-neutral and identical in every host evaluation. The sender and verifier are host-specific interpretations of that shared intent.

## Current state

- `modules/infra/backup/btrbk-replication.nix:69-70` gates the whole sender configuration on Aurora.
- `modules/infra/backup/btrbk-replication.nix:135-156` declares `nori.replicas` **inside** that gate, deriving entries from Aurora's local `nori.fs`.
- `modules/infra/storage/replication.nix:113-123` filters the local registry by `target.host == config.networking.hostName` before emitting units.
- Verified at planning time:

```text
aurora nori.replicas keys:      archive home-videos library photos projects
workstation nori.replicas keys:  <empty>
workstation verifier units:      <empty>
```

- The source paths are `/mnt/family/<dataset>` and target paths are `/mnt/family-replica/<dataset>`.
- Workstation already declares target filesystem entries such as `family-replica-library` in `modules/machines/workstation/disko-mp510.nix:37-40`.

Architecture constraint:

```text
one nori.replicas registry
       ├─ source host writer → btrbk send configuration
       └─ target host writer → replication-verifier units
```

Do not create one registry per host; that recreates the drift class this abstraction is meant to remove.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Targeted eval | `nix build --no-link .#checks.x86_64-linux.eval-replica-placement` | exit 0 |
| Compare registries | `for h in aurora workstation pi pavilion; do nix eval --json .#nixosConfigurations.$h.config.nori.replicas --apply builtins.attrNames; done` | identical five-key arrays |
| Inspect target units | `nix eval --json .#nixosConfigurations.workstation.config.systemd.services --apply 's: builtins.filter (n: builtins.match "replication-verifier-.*" n != null) (builtins.attrNames s)'` | five verifier units |
| Build hosts | `nix build --no-link .#nixosConfigurations.aurora.config.system.build.toplevel .#nixosConfigurations.workstation.config.system.build.toplevel` | exit 0 |
| Full gate | `nix flake check --print-build-logs` | exit 0 |

## Scope

**In scope**:

- `modules/infra/backup/btrbk-replication.nix`
- `modules/infra/storage/replication.nix` — assertions or comments only if needed
- `tests/eval/replica-placement.nix` — create
- `flake.nix`
- `docs/reference/storage.md`
- `docs/generated/replicas.md` — regenerate only

**Out of scope**:

- Changing the replication mechanism, schedule, retention, SSH key, or physical disks.
- Adding pavilion's future tertiary replica.
- Changing snapshot freshness semantics; Plan 008 handles runtime invocation.
- Copying the same five entries into both host modules.
- Reclassifying replica targets as backups.

## Git workflow

- Use an isolated worktree when dispatched.
- Do not deploy, commit, or push unless authorized.
- Suggested commit: `fix(replication): share replica intent across host evals`.

## Steps

### Step 1: Add an eval test that demonstrates the split-brain

Create `tests/eval/replica-placement.nix`, following `tests/eval/route-invariants.nix`.

The test must evaluate source- and target-shaped configurations importing the real backup and storage concerns. Assert:

1. source and target see the same replica keys;
2. Aurora emits `btrbk-family-replica` when enabled;
3. workstation emits one `replication-verifier-<name>` per registry entry targeting workstation;
4. pi emits no verifier units for workstation-target entries;
5. an entry whose source or target host is absent from `nori.hosts` fails eval.

**Verify RED**:

```bash
nix build --no-link .#checks.x86_64-linux.eval-replica-placement
```

Expected: fail because workstation currently sees no entries.

### Step 2: Promote `nori.replicas` to the host-neutral root declaration

In `btrbk-replication.nix`, define the five current family replica entries outside the Aurora-only `mkIf`. This attrset is the one authoritative declaration.

Use explicit dataset names and roots:

```nix
familyReplicaNames = [ "archive" "home-videos" "library" "photos" "projects" ];

nori.replicas = lib.genAttrs familyReplicaNames (name: {
  source = { host = "aurora"; path = "/mnt/family/${name}"; };
  target = { host = "workstation"; path = "/mnt/family-replica/${name}"; };
  mechanism = "btrfs-send-receive";
  maxAgeHours = 25;
});
```

Keep this declaration unconditional so all host evaluations receive it. It is acceptable for non-participant hosts to carry registry data; writers filter by role.

Remove the old `irreplaceableFs`-derived registry declaration. The source dataset list must now be derived from `config.nori.replicas`, not maintained separately.

### Step 3: Derive the Aurora sender from the registry

Inside the Aurora sender gate:

- filter `config.nori.replicas` to entries with source host `aurora`, target host `workstation`, and mechanism `btrfs-send-receive`;
- derive btrbk subvolume names by removing `/mnt/family/` from each `source.path`;
- derive each SSH target from `target.path` and workstation's registered tailnet IP;
- preserve existing schedule, retention, compression, SSH identity, and failure notification.

Add assertions on participant hosts:

- on Aurora, every declared source path exists in `config.nori.fs` and is tier `irreplaceable`;
- on workstation, every target path exists in `config.nori.fs` and is tier `re-derivable`;
- every source and target host is a key in `nori.hosts`;
- source and target roots match the btrbk implementation's supported roots.

These assertions are the derivation-strength substitute for previously deriving directly from local `nori.fs`.

**Verify**:

```bash
for h in aurora workstation pi pavilion; do
  printf '%s: ' "$h"
  nix eval --json ".#nixosConfigurations.$h.config.nori.replicas" --apply builtins.attrNames
 done
```

Expected: identical arrays containing the five names.

### Step 4: Prove the writers land on opposite hosts

Run:

```bash
nix eval --json .#nixosConfigurations.aurora.config.systemd.services \
  --apply 's: builtins.filter (n: n == "btrbk-family-replica") (builtins.attrNames s)'

nix eval --json .#nixosConfigurations.workstation.config.systemd.services \
  --apply 's: builtins.filter (n: builtins.match "replication-verifier-.*" n != null) (builtins.attrNames s)'
```

Expected: Aurora lists the sender; workstation lists five verifier units.

Also inspect one generated verifier:

```bash
nix eval --raw \
  .#nixosConfigurations.workstation.config.systemd.services.replication-verifier-photos.script
```

Expected: script targets `/mnt/family-replica/photos` and uses the 25-hour budget.

### Step 5: Wire docs and run all gates

Update `docs/reference/storage.md` to state that registry data is present on every host while writers activate only on matching source/target hosts. Regenerate the generated artifact exactly:

```bash
nix build .#docs-replicas -o /tmp/docs-replicas-result
cp /tmp/docs-replicas-result docs/generated/replicas.md
chmod +w docs/generated/replicas.md
cmp docs/generated/replicas.md /tmp/docs-replicas-result
```

Do not hand-edit generated prose.

**Verify**:

```bash
nix build --no-link .#checks.x86_64-linux.eval-replica-placement
nix build --no-link \
  .#nixosConfigurations.aurora.config.system.build.toplevel \
  .#nixosConfigurations.workstation.config.system.build.toplevel
nix flake check --print-build-logs
```

Expected: exit 0.

## Test plan

- Layer 1 `eval-replica-placement`:
  - identical registry on source and target;
  - sender only on source;
  - verifier only on target;
  - unknown host references fail;
  - fs path/tier mismatch fails.
- Existing generated-doc freshness check proves schema docs remain synchronized.
- After deployment, Plan 008 will actively run each target verifier. Until then, verify units exist and timers are enabled on workstation.

## Done criteria

- [ ] All four host evaluations expose identical replica keys.
- [ ] Aurora derives sender subvolumes from `nori.replicas`.
- [ ] Workstation emits five verifier services and timers.
- [ ] Source/target path and tier assertions are tested.
- [ ] No duplicate host-local replica declaration exists.
- [ ] Targeted test, host builds, docs freshness, and full flake check pass.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status is updated.

## STOP conditions

Stop if:

- the current five datasets differ from the evaluated Aurora irreplaceable set;
- workstation lacks a target `nori.fs` entry for any dataset;
- deriving btrbk targets from `target.path` changes the effective receive location;
- a host-specific registry is required by an undocumented module-system constraint;
- the fix would require changing SSH credentials or running a real replication job.

## Maintenance notes

- Add future replicas once to `nori.replicas`; source and target writers must derive from it.
- The explicit dataset-name list is acceptable because it is now the authoritative replication set and is checked against both hosts' filesystem registries.
- Pavilion tertiary replication should extend this registry, not create a parallel mechanism.
