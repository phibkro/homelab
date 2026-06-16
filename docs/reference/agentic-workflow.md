---
summary: How per-PR work is shaped, paced, and reviewed when one operator
  drives a rotating cast of amnesiac agents. The four-phase per-PR ceremony
  (preamble / execution / reporting / reflection), the operator-role hats,
  session economics, the CI/CD inversion, and the branching stance. ADR-0005
  is the decision record; this is the working reference.
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

## The per-PR ceremony (four phases)

```
Preamble  →  Execution  →  Reporting  →  Reflection
(scope)      (commits)    (PR review)   (retro)
```

### Phase 1: Preamble — scope before tools

Before any tool call lands, surface:

- **Goal** in one sentence. What does "done" look like?
- **Punch list** the agent will execute. Enumerated, distinct items.
- **Open questions** that need operator input before edits start.
- **Definition of Done** — what makes this PR genuinely complete.

The operator confirms or redirects. **Skipping the preamble is the most-cited miss in the 2026-06-16 docs deep-sweep retro.** Spec-Driven Development calls this "phase-boundary review at spec time"; same pattern, different name.

```
What the agent says, in this shape:

"Goal: ship X. Punch list: a, b, c. Open: should we also y?
DoD: a+b+c green CI + acceptance criterion Z. Proceed?"
```

### Phase 2: Execution — atomic, themed commits

- **One axis per commit.** Stale-rename sweep ≠ content rewrite ≠ refactor. Bundling collapses revertability.
- **Conventional commits** with rich bodies. The body is where future-amnesiac agents recover context; treat it like a PR description that won't be lost.
- **"Intentionally NOT touched"** lists in commit bodies when a sweep deliberately leaves things alone. Prevents future agents from "fixing" historical artifacts.
- **CI green at each commit**, not just at the end. Pre-commit hook + `nix flake check` are the local gates.
- **Mid-sprint checkpoint discipline.** Restate done/verified/left after significant steps (SOUL.md "Knob — checkpoint cadence"). Don't continue from a state you can't describe back.

### Phase 3: Reporting — PR review as checkpoint

Before push, surface a structured rundown:

- **Per-commit grade** (🟢 / 🟡 / 🔴) with one-line justification.
- **Cross-cutting observations.** Patterns across multiple commits, debt accumulated, decisions that may warrant ADRs.
- **Things done right, named.** Not flattery — explicit "we should keep doing X" so the next-amnesiac agent inherits the practice.
- **Recommendation** with action items.

The push gate (per CLAUDE.md § "Push gate") is the formal boundary. Reporting is what makes it a real review and not a rubber stamp.

### Phase 4: Reflection — four questions

Operator-driven; agent answers honestly:

| Question | What it surfaces |
|---|---|
| **What worked, worth keeping?** | Practices to reinforce. Includes things the agent did unprompted that should become explicit. |
| **What's our Definition of Done? Did we hit it?** | If no DoD was set up front (preamble miss), define post-hoc and self-grade. |
| **What could we do better next sprint?** | Concrete misses; ideally with mechanization moves to prevent recurrence. |
| **Did we leave the codebase clean for the next amnesiac team?** | Plan files updated? Debt named where it'll be found? Memory/specs/CLAUDE.md current? |

The 2026-06-16 retro caught: no preamble confirmation, no DoD up front, plan progress log empty, one commit missing trailer, no mid-sprint checkpoints. Each surfaced via this four-question form. None would have been caught by the operator's PR review alone.

## Ceremony adoption matrix

| Scrum ceremony | Verdict | Agentic shape |
|---|---|---|
| Sprint planning | **ADOPT** as Preamble | Phase 1 above. Phase-boundary review before tools fire. |
| Daily standup | **SKIP** as ceremony, IMPLICIT via topology | Subagent reports + main-agent `TaskCreate` self-tracking. Reporting is in the agent collaboration topology, not a meeting. |
| Sprint review | **ADOPT** as Reporting | Phase 3 above. Precedes the push gate. |
| Retrospective | **ADOPT** as Reflection | Phase 4 above. Per-PR, not per-session (sessions decoupled from PRs per [[session-economics]]). |
| Backlog refinement | **ALREADY EXISTS** | `docs/roadmap.md`. Edit in place; no recurring meeting. |
| Story sizing / estimation | **SKIP** | Agents don't have meaningful velocity. The estimate analog is "does this fit in one session within budget?" — handled by session-economics. |
| Mid-sprint course correction | **ADOPT** (always-available) | Operator can redirect any turn. No formal ceremony; just an invariant of the model. |

## Operator-role hats

The operator wears four hats simultaneously. Naming them is informational — knowing which hat is on at a given decision sharpens the call.

| Hat | Decides | When worn |
|---|---|---|
| **PM** | scope, acceptance criteria, scope creep | Preamble; mid-sprint redirects |
| **Tech lead** | architectural decisions (ADRs) | When a design call exceeds the agent's surface visibility |
| **Scrum master** | ensures the ceremony actually happens | At phase boundaries; catches missed preambles / reflections |
| **Reviewer** | merge / push approval | Phase 3 (reporting) + the push gate |

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
spans two sessions runs reflection at PR-end, not at first
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

- **Spec-Driven Development (SDD)** — the phase-boundary review pattern (spec → plan → tasks → impl) maps onto Preamble. We adopt the pattern, not the full machine-readable-spec framing (most PRs are too small).
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
- `home/claude-code/skills/brainstorming/SKILL.md` — existing preamble-shaped ceremony (overlap with Phase 1)
- `home/claude-code/skills/dev-loop/SKILL.md` — workflow map; due for refresh against this doc
