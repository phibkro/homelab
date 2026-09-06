# Docs-shape review (post-aurora-migration)

> **Source of truth** for the docs reshuffling. Decisions already made are captured here so a future-me starting Phase 17 inherits them rather than re-deriving them.

**Goal:** Make the docs structure itself encode read priority. The current flat `docs/*.md` layout treats every reference doc as equally important to discover; the cost of reading them isn't equal and the structure should reflect that.

**Trigger:** Main pass after Phase 17 of the aurora migration (replication + verification stable, architectural moves done). Quick second pass after Phase 20 (steady-state confirmation).

**Methodology:** Same shape as the architecture work — clean-slate ideal → delta table → phased execution → measurable outcome.

---

## Target shape

Depth-in-the-filesystem encodes tier. The existing convention (CLAUDE.md at the repo root rather than `docs/`) already does this; we just extend it consistently.

```
/
├── CLAUDE.md                  L0   always loaded (system reminder)
├── README.md                  L0   project entry
├── GLOSSARY.md                L1   mandatory at session start
├── INVARIANTS.md              L1   mandatory at session start
├── docs/
│   ├── README.md              L2   routing map mirror
│   ├── topology.md            L2   topic-triggered reference
│   ├── storage.md             L2
│   ├── network.md             L2
│   ├── services.md            L2
│   ├── module-authoring.md
│   ├── documentation-writing.md
│   ├── enforcement.md
│   ├── recovery.md
│   ├── runtime-tests.md
│   ├── capacity-baseline.md
│   ├── skill-index.md
│   ├── decisions/             L3   ADRs (0000-rationales as the meta-index)
│   ├── runbooks/              L3
│   ├── specs/                 L3
│   ├── docs/archive/legacy-plans/                 L3
│   └── installs/              L3   baremetal + vm + agent-onboarding-test
└── (PROJECTS.md → /srv/share/projects/AGENTS.md, out of homelab)
```

Read-cost trickle for an amnesiac agent:

```
session start
    ↓
[L0] CLAUDE.md auto-injected; routing map + hard rules
    ↓
[L1] GLOSSARY + INVARIANTS read unconditionally (vocabulary + load-bearing claims)
    ↓
task topic identified
    ↓
[L2] docs/<topic>.md fetched on demand
    ↓
cross-reference encountered
    ↓
[L3] docs/<subfolder>/<specific>.md fetched only when led to
```

The depth signals the read-bar: deeper = read only when the system tells you to.

---

## Decisions already made (captured 2026-06-11)

Locked in via conversation; not to re-litigate at Phase 17:

| Question | Decision |
|---|---|
| Folder naming | Implicit depth (root / docs/ / docs/sub/) — no `L1`/`tier-1`/`mandatory` prefixes. The convention "deeper = harder to fetch = read on stronger trigger" is the documentation. |
| What counts as L1 | Unconditional-read only: GLOSSARY + INVARIANTS. `documentation-writing.md`, `module-authoring.md`, etc. stay L2 because they're conditional on the agent doing that kind of work. |
| PROJECTS.md | Leaves homelab; unify canonical home at `/srv/share/projects/AGENTS.md`. |
| RATIONALES | Become `docs/decisions/0000-rationales.md` — meta-index ADR that lists small rationales not big enough for full ADRs. |
| superpowers/{specs,plans}/ | Flatten to `docs/{specs,plans}/`. The "superpowers" name doesn't earn rent. |
| Flake-check structure enforcement | Yes — add a check asserting CLAUDE.md's routing tables match `docs/` filesystem layout. Prevents drift. |
| CLAUDE.md size budget | Tight: routing map + hard rules + bias + how-to-operate. After this lands, most of the docs-map prose can be derived/asserted from filesystem. |

---

## Open decisions for Phase 17

The reshuffling needs these settled, but they're small enough to handle in-flight:

1. **Filename case.** Today UPPER_SNAKE_CASE signals top-level reference and lower-kebab signals procedural. With depth encoding tier, case becomes redundant. Probably unify to lowercase-kebab everywhere, but that's a separate sub-decision. Default: lowercase-kebab for all new files; rename existing as part of the move.

2. **Does `docs/README.md` survive?** Currently it mirrors the CLAUDE.md tables. After the flake check enforces structure, the map becomes derivable. Either keep README.md as the human-readable mirror, or generate it from filesystem at build time. Defer.

3. **Skills + memory restructuring.** The conversation surfaced that skills + memory follow the same tier semantics (gotcha-* = L0-auto-load, workflow skills = L1, etc.). Whether to actually restructure those during this pass or defer to a separate session. Default: include in the audit, defer execution if scope blows up.

4. **Outdated content during the move.** Some docs have post-aurora content drift (TOPOLOGY, STORAGE, RECOVERY). The reshuffling shouldn't be a content-rewrite sweep, but obvious staleness gets flagged. Defer big content rewrites to a separate pass.

---

## Migration phases

| Phase | What | Validation |
|---|---|---|
| **D1** | Move GLOSSARY + INVARIANTS to root | `nix flake check` green; CLAUDE.md table updated to reference new paths |
| **D2** | Add flake check for routing-table-vs-filesystem consistency | Check fails on a synthetic drift, passes on the real state |
| **D3** | Migrate RATIONALES → `docs/decisions/0000-rationales.md` (meta-index) | Existing rationale entries preserved + structured as ADR-index |
| **D4** | Flatten `superpowers/{specs,plans}/` → `docs/{specs,plans}/` | Internal cross-references updated (rg for old paths) |
| **D5** | Group installs: `baremetal-install.md`, `vm-install.md`, `agent-onboarding-test.md` → `docs/installs/` | Same |
| **D6** | Move PROJECTS.md → `/srv/share/projects/AGENTS.md` as canonical; symlink (or remove) the homelab copy | `ls -la` confirms the layout the operator expects |
| **D7** | Rename files to consistent case (if filename-case decision lands as "unify lowercase") | All filenames lowercase-kebab |
| **D8** | Trim CLAUDE.md to load-bearing minimum — routing map + hard rules + bias + operating notes. Drop the duplicate explanations where filesystem now documents itself. | CLAUDE.md halved-ish; agent-onboarding test still passes |
| **D9** | Skill SKILL.md audit — same tier lens; defer restructuring if scope blows up | Per-skill review notes captured |
| **D10** | Memory audit — same tier lens applied to MEMORY.md indexing + individual entries | Per-entry review notes captured |

Phase 20 quick pass: re-walk the structure after a couple of steady-state weeks. Look for "did anything want to be in a different tier than we placed it?"

---

## Validation gates

- Per phase: `nix flake check` green (especially the new structure-vs-routing-table check from D2)
- Per phase: at least one path that an agent would actually follow (e.g. "an agent that needs to add a service" → still reaches `add-service` skill via the right path)
- Final: `docs/installs/agent-onboarding-test.md` (already exists for validating agent orientation) passes with the new structure
- Operator subjective: "would a fresh agent landing on this find the right thing fast?"

---

## Not in scope for this pass

- Big content rewrites of L2 reference docs (handled if/when the content drifts past acceptable; not the structural pass's job)
- Replacing CLAUDE.md's hard rules + bias content (those are decisions, not structure)
- ADR-0001 / ADR-0002 content (existing ADRs are fine; only their location may move if/when the decisions folder relocates — which is not planned in this pass)

---

## References

- `docs/decisions/0001-agentic-homelab-practices.md` — meta-ADR; the "amnesiac team" model that makes progressive disclosure the right answer
- `docs/reference/documentation-writing.md` — earns-rent taxonomy; structural choices honour the same principle
- `docs/archive/plans/2026-06-11-aurora-migration.md` — sibling plan; same methodology applied to architecture
