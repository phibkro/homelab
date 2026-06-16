# Docs deep sweep — drift + restructure + alignment

> **Source of truth** for the homelab documentation overhaul. Captures the phases, the rationale, and the deferred sub-decisions so a fresh agent landing on this can resume any phase without re-deriving the framing. Updated as phases land.

**Goal:** A unified pass over every doc-shaped artifact in the homelab (and the operator's adjacent global config) that closes three gaps simultaneously:

1. **Drift** — claims that no longer match code or reality (this session alone produced ≥4 named cases)
2. **Structure** — read-cost not matching read-priority; the existing tier-1/2/3 convention isn't reflected in the filesystem layout yet
3. **Alignment** — SOUL.md axioms (single-source-of-truth, three-boundaries correctness, name-right-answer-first) not yet reflected downstream

**Path chosen:** Phased; inventory before edits; surgery one tier at a time; validation against `docs/agent-onboarding-test.md` at the end.

---

## Relation to existing docs-shape-review

This plan **absorbs and extends** `docs/superpowers/plans/2026-06-11-docs-shape-review.md` (the structural-only pass). That plan's `D1–D10` are the surgery sub-phases under this plan's Phase 3. Decisions captured there 2026-06-11 (folder naming, what counts as L1, PROJECTS.md exit, RATIONALES → ADR-index, superpowers flatten, flake-check structure enforcement, CLAUDE.md size budget) carry forward unchanged unless explicitly re-litigated in Phase 2.

This plan **adds** two passes the structural-only review explicitly deferred:

- Drift catalog (new — Phase 1)
- Content alignment to SOUL.md axioms (new — folded into Phase 3 surgery)

If you're a fresh agent and see both plans: read this one. The 2026-06-11 plan is the structural skeleton that lives inside Phase 3 here.

---

## Trigger

Three forcing functions converged:

1. **This session's architectural decisions produced doc drift** the codebase doesn't catch. Examples surfaced live:
   - P15 status reads "awaits operator ssh-key bootstrap" but has been running daily since Jun 11
   - `docs/superpowers/reports/2026-06-aurora-migration.md` says `/mnt/family-replica/*` is "currently empty" — it's populated, replicating nightly
   - `library/{books,music}` semantic just inverted (library = curated-keepers, downloads = re-derivable acquisitions); nothing in docs reflects this yet
   - Gatus `runsOn` flipped from workstation to pi; the topology doc doesn't know
   - Syncthing now runs on both workstation and aurora; the module doc + RATIONALES don't reflect the bidirectional intent

2. **SOUL.md restructure (2026-06-15, d01876f)** introduced new axioms — particularly **Single Source of Truth** with its derivation-strength ladder (`generate > test > convention`). Many docs paraphrase code rather than reference it; that's the rent-not-paid antipattern the new axiom names.

3. **The 2026-06-11 docs-shape-review never executed.** The structural reshuffling is overdue, and the longer it waits, the more content layers on top of the wrong structure.

---

## Methodology

```
read-only pass first       ──▶  decide what target state is        ──▶  edit
(inventory, catalog drift)      (restructure shape, alignment moves)     (one tier at a time)
                                          │
                                          ▼
                                  validate fresh-agent
                                  orientation works
```

Same shape as the aurora migration plan: clean-slate ideal → delta table → phased execution → measurable outcome. Each phase is its own session-worth of work. The transition between phases is the operator-approval gate.

---

## Phase 1 — Inventory + drift catalog

**Goal:** A single document that enumerates every doc + memory + skill description in scope, with each entry tagged for:

- **Drift findings:** specific claims that don't match code or reality (e.g., "STATUS.md line 47 says P15 awaits bootstrap; live since Jun 11")
- **Structural observations:** tier mismatch, duplicate-with, should-be-derived, missing-cross-ref
- **Alignment gaps:** where SOUL.md axioms are violated (`name-right-answer-first`, SoT, three-boundaries, constraints-generative)

**Scope:**

- `CLAUDE.md` (root), `README.md`
- `docs/*.md` (all tier-1 + tier-2 files)
- `docs/decisions/*.md`
- `docs/superpowers/reports/*.md` + `docs/superpowers/plans/*.md`
- `docs/runbooks/*.md`
- `docs/baremetal-install.md`, `docs/vm-install.md`, `docs/agent-onboarding-test.md`
- `home/claude-code/CLAUDE.md` (SOUL.md — the operator's global config)
- `~/.claude/projects/-srv-share-projects/memory/MEMORY.md` + entries

**Out of scope for Phase 1:**

- `.claude/skills/gotcha-*/SKILL.md` (numerous; deferred to Phase 3 audit unless drift surfaces from elsewhere)
- Service-module comments (separate `audit-documentation` skill territory; handled per-module, not in this sweep)

**Output:** `docs/superpowers/reports/2026-06-XX-docs-inventory.md` — a structured catalog. Ranked punch list of drift + structural-finding-per-doc + alignment-finding-per-doc.

**Execution:** Spawn an Explore agent to do the read-through in one parallel pass; receive the report into the surgery context.

**Validation:** Operator confirms the catalog matches their intuition for "what's broken." Adjusts ranking if priorities differ.

---

## Phase 2 — Restructure decisions

**Goal:** Lock in the target state — tree shape, tier assignments, file renames, content boundaries. No code yet.

**Inputs:**

- Phase 1 catalog
- The `D-` decisions already captured in `2026-06-11-docs-shape-review.md` § "Decisions already made"
- The open decisions from the same doc (filename case, README.md survival, skills+memory restructure, drift-during-move handling)

**Possible new decisions surfaced by Phase 1 (placeholders):**

- Whether content-rewrite sub-phases interleave with structural sub-phases, or run as a separate pass after structural lands
- Whether SOUL.md alignment is a per-doc-rewrite move or a separate ADR codifying the alignment principles
- Whether memory entries get their own restructure pass or fold into the broader sweep

**Output:** `docs/superpowers/specs/2026-06-XX-docs-target-state.md` — the target outline. Tree shape, file map (old → new), per-file content boundaries, SOUL.md alignment principles applied.

**Validation:** Operator approves before any file is touched.

---

## Phase 3 — Surgery, by tier

One commit per logical group (file or related-file-cluster). Each surgery sub-phase has the same shape:

```
read current state  →  draft replacement  →  diff review with operator
                                                       ↓
                                                  apply edits
                                                  → nix fmt
                                                  → nix flake check
                                                  → commit
```

**Sub-phases:**

| Tier | What | Notes |
|---|---|---|
| **T0** | `CLAUDE.md` (entrypoint) | Smallest possible; routing + hard rules + bias + how-to-operate; per `2026-06-11-docs-shape-review` D8 |
| **T1** | `GLOSSARY.md`, `INVARIANTS.md` | Promote to repo root (per D1); content alignment to SOUL.md axioms; INVARIANTS picks up the three-boundaries frame at the top |
| **T2-storage** | `TOPOLOGY.md`, `STORAGE.md`, `NETWORK.md`, `capacity-baseline.md` | Topic-triggered; absorb drift (library/downloads semantic, P15-live, gatus-on-pi) |
| **T2-services** | `SERVICES.md`, `MODULE_AUTHORING.md`, `RUNTIME_TESTS.md` | Drift + alignment; ensure single-source-of-truth axiom is honoured (no duplicate lists derivable from code) |
| **T2-meta** | `DOCUMENTATION_WRITING.md`, `ENFORCEMENT.md` | These are doctrine docs; alignment with SOUL.md is the main edit |
| **T2-ops** | `RECOVERY.md`, `RATIONALES.md` (or new `docs/decisions/0000-rationales.md` per D3), `ROADMAP.md`, `SKILL_INDEX.md`, `PROJECTS.md` (move per D6) | Drift-heavy; many ROADMAP entries will move from outstanding to landed |
| **T3** | `docs/decisions/`, `docs/superpowers/reports/`, `docs/superpowers/plans/`, `docs/runbooks/`, install docs (group per D5) | Mostly drift fixes; structural moves per existing D-phases |
| **T-mem** | `~/.claude/projects/-srv-share-projects/memory/MEMORY.md` + entries | Same lens; flag any entries whose claims went stale this session |
| **T-soul** | `home/claude-code/CLAUDE.md` (SOUL.md) | If Phase 1 surfaces gaps in the axioms themselves, fold here; otherwise minimal |

**Commit cadence:** One commit per sub-phase or per file, whichever is smaller. Conventional-commit style (`docs(<scope>): <subject>`). Push gate per `CLAUDE.md` — surface diff before pushing.

---

## Phase 4 — Validation

**Goal:** Confirm a fresh-context agent gets oriented through CLAUDE.md → docs/ and lands at the right answer.

**Mechanism:**

- Run `docs/agent-onboarding-test.md` (existing validation skill) with a fresh sub-agent. Pick a small fixed task — e.g., "add a new service to the homelab" — and observe whether the agent reaches the right docs in the right order.
- Operator subjective check: "would a fresh agent landing on this find the right thing fast?"
- `nix flake check` clean (especially the routing-table-vs-filesystem check from `2026-06-11-docs-shape-review` D2 if it landed)

**Reversal ladder:** Each phase is reversible by git revert at the commit level. The biggest risk is structural file moves breaking external references (CLAUDE.md routing tables, skill triggers, memory cross-refs) — Phase 3's per-file commits keep the blast radius bounded.

---

## Out of scope (will be deferred)

- **Big content additions** beyond what's needed to close drift. If the sweep surfaces "this doc should also cover X," that's a separate follow-up (new ADR or doc).
- **Service-module code comments.** The `audit-documentation` homelab skill covers that domain; running it across modules is a sibling exercise, not this sweep.
- **Replacing CLAUDE.md's hard rules + bias content** (those are decisions, not structure). Per `2026-06-11-docs-shape-review` "not in scope."
- **Gotcha skill SKILL.md sweep.** Per Phase 1 scope cap. Defer to a focused gotcha-audit session.
- **Memory restructure execution.** Phase 1 inventories; Phase 3 T-mem may apply small edits; full restructure is its own decision tree.

---

## Open questions for Phase 2

These will be settled in Phase 2 once Phase 1's catalog is in hand:

1. **Interleave or separate** content rewrites vs structural moves? Risk of one: bigger commits, harder revert. Risk of the other: two passes over the same files, doubled cognitive cost.
2. **SOUL.md alignment principles** — codify as ADR or fold into `DOCUMENTATION_WRITING.md`?
3. **Memory restructure** — execute during this sweep or defer to a separate session per scope?
4. **Filename case unification** — per existing D7 default (unify to lowercase-kebab); confirm with operator at Phase 2.
5. **`docs/README.md` survival** — generate from filesystem at build time, keep as human mirror, or kill?

---

## Cross-references

- `docs/superpowers/plans/2026-06-11-docs-shape-review.md` — the structural skeleton this sweep absorbs
- `docs/superpowers/plans/2026-06-11-aurora-migration.md` — sibling plan; same methodology applied to architecture; canonical example of the "amnesiac-resumable plan" form
- `docs/decisions/0001-agentic-homelab-practices.md` — meta-ADR; the "amnesiac team" model that makes progressive disclosure load-bearing
- `docs/DOCUMENTATION_WRITING.md` — the earns-rent taxonomy and anti-patterns; the lens for Phase 3 content edits
- `docs/ENFORCEMENT.md` — the prose→comment→test→type ladder; many Phase 3 alignment edits will push claims down this ladder
- `home/claude-code/CLAUDE.md` (SOUL.md) — the axioms to align downstream docs against
- `docs/agent-onboarding-test.md` — Phase 4 validation harness

---

## Progress log

Updated as phases land.

| Date | Phase | Outcome |
|---|---|---|
| 2026-06-16 | plan persisted | (this file) |
