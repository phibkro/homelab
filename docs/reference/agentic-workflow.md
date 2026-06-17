---
summary: How per-PR work is shaped, paced, and reviewed when one operator
  drives a rotating cast of amnesiac agents. The three-phase per-PR ceremony
  (prologue / execution / epilogue) — problem definition + solution research
  up front; keyframe-then-inbetween execution; reporting + verification +
  retrospective at end. Plus operator-role hats, session economics, the
  CI/CD inversion, and the branching stance. ADR-0005 is the decision
  record; this is the working reference.
---

# Agentic workflow

The homelab is built by **one persistent operator** + **agents that rotate per session**. Traditional agile presumes persistent humans across time; that's the load-bearing presumption to drop. ADR-0001 named the filter for which practices transfer (*externalizes knowledge OR verifies a claim*); ADR-0005 decides ceremony-by-ceremony shape within the surviving set. This doc is the working reference.

## The shape at a glance

```
┌─────────────────────────────────────────────────────────────┐
│ Operator (persistent)                                       │
│   wears: PM hat · TL hat · scrum master hat · reviewer hat  │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ scopes PR, reviews at boundaries
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Agent (rotates per session — amnesiac at session boundary)  │
│   reports up via subagent topology                          │
└─────────────────────────────────────────────────────────────┘

The unit of work is the PR (= one feature or in-depth improvement,
not a fix). One PR can fit in a session; multiple PRs can share
a session if context budget allows; one PR can span sessions if
context burns fast. PR and session are decoupled — see
[[session-economics]] memory.
```

## The per-PR ceremony (three phases)

```
Prologue            Execution             Epilogue
(problem +    →     (keyframes +    →    (reporting +
 research)           inbetweens)           retrospective)
```

The phases match the natural arc: define the problem, solve it, then look back. Each phase has internal structure but the boundary between them is the load-bearing surface — those are where the operator review gate fires.

### Phase 1: Prologue — define the problem before solving it

Before any tool call lands, the agent surfaces a problem definition and a solution sketch for operator review.

**Define the problem (3 axes):**

| Axis | What | Analog |
|---|---|---|
| **Goal** | Verifiable success criterion. What does "done" look like, and how do we know? | Functional requirement; the acceptance test |
| **Constraints** | Hard invariants — what must NOT happen. Deal-breakers. | Negative feedback; the guardrails |
| **Values** | Soft invariants — preferences (e.g. UX, security, simplicity). Trade-offs handled here. | Non-functional requirements; the system qualities |

The Goal is verifiable; the Constraints are categorical; the Values are negotiable but explicit. A problem definition that conflates the three produces an under-constrained solution (and the agent fills the gap with assumptions, often wrong).

**Research the solution space:**

- **Existing conventional solutions** — what does the field do? (e.g. for "lint commit subjects": commitlint is the de facto answer.)
- **State of the art** — what's the most-correct framing, even if expensive?
- **Adopt or inspire** — pick the existing solution, or extract the shape and re-implement against project constraints.

SOUL.md "name the right answer first" applies: state the right answer *before* compromising. Premature pragmatism assumes constraints that don't apply.

**Gate — is the solution satisfactory?**

```
                ┌─────────────────┐
                │ Solution viable?│
                └────────┬────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
             YES                    NO
              │                     │
              ▼                     ▼
          Execution           Refine the problem:
                              clarify Goal / Constraints
                              / Values to narrow the space,
                              then re-research.
                              (Repeat until viable.)
```

**Output of the Prologue:** scope + DoD with Goal/Constraints/Values explicit, candidate solution named, open questions surfaced. Operator confirms or redirects.

Skipping the Prologue is the most-cited miss in the 2026-06-16 docs deep-sweep retro. Spec-Driven Development calls the equivalent "phase-boundary review at spec time"; same pattern.

### Phase 2: Execution — keyframes, then inbetweens

The split between *control plane* (what the work is) and *data plane* (how it's implemented) shapes the execution model. Specs and tests are the control plane; commits are the data plane.

**Keyframes-not-full-specs:**

```
Spec mode                            Keyframe mode
─────────                            ─────────────
Spec every line.                     Spec the end goal + critical
Agent transcribes.                   waypoints. Agent draws the
                                     inbetweens for the project.

Over-constrains. Agent has no        Encodes WHAT (verifiable),
freedom to find the project-fit      lets agent pick HOW. Inherits
implementation. Brittle to spec      project-fit, more robust to
drift.                               drift.
```

Think of a spec like keyframes in an animation: the end goal + critical waypoints have verifiable Definitions of Done; the inbetweens are the agent's craft. The operator reviews keyframes; the inbetweens are caught by tests + the Epilogue.

**TDD as keyframe encoding:**

Red-green TDD is unusually effective for agentic dev: tests encode behavior into the control plane *executably*. The keyframe's DoD is "this test passes"; the agent's freedom is "any code path that gets there." Reach for it whenever the behavior is verifiable but the implementation is open. See `docs/reference/runtime-tests.md` for the homelab's four-lever framework for choosing when a test earns its keep.

**Practical execution discipline (the in-between craft):**

- **One axis per commit.** Stale-rename sweep ≠ content rewrite ≠ refactor. Bundling collapses revertability.
- **Conventional commits** with rich bodies — enforced by `.githooks/commit-msg` on the subject (hard constraint); body quality reviewed in the Epilogue (soft constraint).
- **"Intentionally NOT touched"** lists in commit bodies when a sweep deliberately leaves things alone. Prevents future agents from "fixing" historical artifacts.
- **CI green at each commit**, not just at the end. Pre-commit hook + `nix flake check` are the local gates.
- **Mid-sprint checkpoint discipline.** Restate done/verified/left after significant steps (SOUL.md "Knob — checkpoint cadence"). Don't continue from a state you can't describe back.

### Phase 3: Epilogue — reporting + retrospective

Two activities, one mode: looking back. Both fire before the push gate.

**Reporting — describe what changed:**

PR-review-style structured rundown:

- **Per-commit grade** (🟢 / 🟡 / 🔴) with one-line justification
- **Cross-cutting observations** — patterns across commits, debt accumulated, decisions that may warrant ADRs
- **Things done right, named** — not flattery; explicit "we should keep doing X" so the next-amnesiac agent inherits the practice
- **Recommendation** with action items
- **Diff size — quoted verbatim, not estimated.** Paste the literal output of `git diff --shortstat origin/main..HEAD` (e.g. `48 files changed, 1234 insertions(+), 567 deletions(-)`) into the report. Estimating diff size invites the 50%-off self-grade the 2026-06-17 PR-review reviewer caught. The mechanization is "run the command, paste the output" — zero estimation surface.

**Verification — did we solve the Prologue's problem?**

Against the Prologue's Goal, Constraints, Values:

| Check | Pass criteria |
|---|---|
| **Goal hit?** | Acceptance test green; DoD items checked |
| **Constraints respected?** | No hard invariants violated (none of the named deal-breakers happened) |
| **Values honored?** | Trade-offs went the way the Values implied; if not, named explicitly |

If the answer to any of these is "no" or "partially," the work isn't actually done — push gate doesn't open, scope re-opens.

**Retrospective — self-reinforcing improvement:**

Four questions, operator-driven, agent answers honestly:

| Question | What it surfaces |
|---|---|
| **What worked, worth keeping?** | Practices to reinforce. Includes things the agent did unprompted that should become explicit. |
| **Did we hit the DoD from the Prologue?** | Self-grade against what was set up front. If no DoD was set (Prologue miss), define post-hoc and grade — and capture the miss. |
| **What could we do better next PR?** | Concrete misses; ideally with mechanization moves to prevent recurrence (promote prose → comment → test → law per `docs/invariants.md`). |
| **Did we leave the codebase clean for the next amnesiac team?** | Plan files updated? Debt named where it'll be found? Memory / specs / CLAUDE.md current? |

The 2026-06-16 retro caught: no Prologue confirmation, no DoD up front, plan progress log empty, one missing trailer, no mid-sprint checkpoints. Each surfaced via the four-question form. None would have been caught by the Reporting phase alone — Reporting describes; Retrospective questions.

## Ceremony adoption matrix

| Scrum ceremony | Verdict | Agentic shape |
|---|---|---|
| Sprint planning | **ADOPT** as Prologue | Phase 1 above. Goal / Constraints / Values + solution research + viability gate, before any tool call. |
| Daily standup | **SKIP** as ceremony, IMPLICIT via topology | Subagent reports + main-agent `TaskCreate` self-tracking. Reporting is in the agent collaboration topology, not a meeting. |
| Sprint review | **ADOPT** as Epilogue § Reporting | Phase 3 above. Precedes the push gate. |
| Retrospective | **ADOPT** as Epilogue § Retrospective | Phase 3 above. Per-PR, not per-session (sessions decoupled from PRs per [[session-economics]]). |
| Backlog refinement | **ALREADY EXISTS** | `docs/roadmap.md`. Edit in place; no recurring meeting. |
| Story sizing / estimation | **SKIP** | Agents don't have meaningful velocity. The estimate analog is "does this fit in one session within budget?" — handled by session-economics. |
| Mid-sprint course correction | **ADOPT** (always-available) | Operator can redirect any turn. No formal ceremony; just an invariant of the model. |

## Operator-role hats

The operator wears four hats simultaneously. Naming them is informational — knowing which hat is on at a given decision sharpens the call.

| Hat | Decides | When worn |
|---|---|---|
| **PM** | scope, acceptance criteria, scope creep | Prologue; mid-sprint redirects |
| **Tech lead** | architectural decisions (ADRs) | When a design call exceeds the agent's surface visibility |
| **Scrum master** | ensures the ceremony actually happens | At phase boundaries; catches missed prologues / retrospectives |
| **Reviewer** | merge / push approval | Epilogue § Reporting + the push gate |

Same person, four hats. The agent's job is to surface the decision so the operator can put the right hat on consciously.

## Session economics

Sessions and PRs are decoupled. Heuristic from [[session-economics]] memory:

```
Keep working in the current session until either:
  - ~20% context remaining, OR
  - ~3 compactions have happened

Then round off: save state to memory, commit persistent artifacts,
hand off cleanly. A fresh session at full context + 30-second
reorient beats a near-full session running on compaction summaries.

Per-PR ceremonies fire regardless of session boundary. A PR that
spans two sessions runs the Epilogue at PR-end, not at first
session-end.
```

This is the "session = sprint" framing from the seed spec, corrected for budget reality.

## CI/CD inversion

Traditional dev: heavy remote CI, light local checks. Agentic dev inverts:

| Layer | Traditional | Agentic |
|---|---|---|
| **Local** | lightweight (lint) | heavyweight (pre-commit `nix flake check` + `commit-msg` Conventional Commits check, all guard derivations, format check) |
| **Remote** | heavyweight CI/CD | backstop only — catches what local skipped (commits from a host without nix on PATH, `--no-verify` bypasses, agent-skipped hooks) |

Why: agents run shell tools locally; "before push" is the cheap fail-fast loop. Catching it on push remote means a roundtrip per failure and noise.

### Hard constraints vs soft constraints

Static checks are reserved for invariants that must hold every turn — commit subject grammar, port uniqueness, schema validation, file-path conventions. The retrospective + PR review (Phase 3) catches everything else.

| Constraint kind | Enforcement | Examples |
|---|---|---|
| **Hard** (invariant) | Static check at commit / build time | Conventional Commits subject; `every-service-has-fs-hardening`; `forbidden-patterns`; `routing-coherence` |
| **Soft** (preference) | PR review + prompting | Commit body quality; prose tone; comment depth; "is this comment earning rent?" |

Static analysis on prose body would be brittle and false-positive-heavy. Soft constraints are caught by Phase 3 (Reporting) — when the operator runs through the per-commit grade, body quality + reasoning depth are surfaced and either accepted or pushed back on.

Same principle as `docs/invariants.md` § "When to add a rule" applied to commit hygiene.

### Local hooks today

- **`.githooks/pre-commit`** — runs `nix flake check` on staged `.nix` changes; skips gracefully if `nix` isn't on PATH.
- **`.githooks/commit-msg`** — enforces Conventional Commits v1.0.0 on the subject line. Hand-rolled bash; pinned to spec v1.0.0; escalation to `nix shell nixpkgs#commitlint-rs` if regex outgrows itself. Bypass with `--no-verify`.

Enable once per clone: `git config core.hooksPath .githooks`.

## Branching + PRs

ADR-0001 rejected feature branches on the no-humans-to-coordinate axis. ADR-0005 revisits on the operator-cognitive-load + blast-radius axis and concludes:

- **Default: commits on `main`.** Atomic per-axis commits + per-commit-revert as the reversibility ladder. The 2026-06-16 docs sweep used this shape across 17 commits with no incident.
- **Worktrees for non-routine refactors.** Per existing CLAUDE.md guidance, reserved for risky structural moves where out-of-tree review pays off. Skill: `using-git-worktrees`.
- **PRs (= GitHub-style review) not used.** Solo-with-agent doesn't benefit from the GitHub review surface; the PR-review-as-Reporting phase happens in-session before push. Push gate per CLAUDE.md is the operator's manual review.

No structural change from current practice; this is the codification of what already works.

## Documentation as transmission medium

The amnesiac-team wrinkle (ADR-0001) makes docs primary, not secondary. Each PR's docs work should be reviewed against:

- **Plan file progress log up to date?** Future-amnesiac agent landing on the plan should see what landed without git log archeology. Caught as miss in 2026-06-16 retro (plan progress log was empty).
- **Debt left in tree named where a fresh agent finds it?** Either in the plan file's "known debt" section, in `docs/roadmap.md`'s "architectural debt", or as a tagged TODO with context.
- **Memory entries created for surprising facts.** Not architecture or code shape (those live in code/docs); only surprises, gotchas, and operator preferences.
- **Specs graduated when they become decisions.** Research-grade specs in `docs/specs/` → ADRs in `docs/decisions/` when the decision lands.

## Prior art / external practice

External references for the homelab's specific take:

- **Spec-Driven Development (SDD)** — the phase-boundary review pattern (spec → plan → tasks → impl) maps onto the Prologue. We adopt the pattern, not the full machine-readable-spec framing (most PRs are too small).
- **BMAD framework** (Breakthrough Method of Agile AI-Driven Development) — confirms documentation-first as drift mitigation; assumes team-of-agents shape that doesn't fit our one-agent + one-operator model.
- **Scrum.org "Sprint Retrospective with half-AI team"** — independently converges on "token burn rate as first retro agenda item" (our [[session-economics]] memory) and "data-driven debugging, not emotional reflection" (our four-question form).
- **Anthropic Claude Cowork (2026-01-12)** — non-developer-focused; tangentially related.

## See also

- `docs/decisions/0001-agentic-homelab-practices.md` — the practice-transfer filter
- `docs/decisions/0005-agile-for-agents-ceremonies.md` — this doc's authoritative decision record
- `docs/specs/2026-06-16-agentic-development-workflow.md` — research seed + worked example (2026-06-16 docs deep-sweep retro)
- [[session-economics]] — when to start a fresh session
- `home/claude-code/skills/wrap-session/SKILL.md` — existing end-of-session ceremony
- `home/claude-code/skills/wrap-feature/SKILL.md` — existing per-feature ceremony (overlap with Phase 4 retro)
- `home/claude-code/skills/brainstorming/SKILL.md` — existing prologue-shaped ceremony (overlap with Phase 1)
- `home/claude-code/skills/dev-loop/SKILL.md` — workflow map; due for refresh against this doc
