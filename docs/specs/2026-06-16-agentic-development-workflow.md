---
summary: Research seed for adapting agile/scrum ceremonies + artifacts to
  agentic development. The wrinkle vs traditional agile is that each session
  is a fresh amnesiac team — the human operator becomes the persistent
  product manager + reviewer, while every "developer" is replaced between
  sprints. Captures the seed observations; the actual research + decisions
  land in a separate session after the docs deep-sweep wraps.
status: research seed — no decisions yet
trigger: 2026-06-16 mid-session, after operator + agent discussion of lint
  rule schema (Phase 3d) surfaced the underlying pattern: declarative
  input + executor + operator-gated review unit. Same shape repeats at
  every layer.
---

# Spec — Agentic development workflow research

> **Open research, not a plan.** Captured as a seed so the actual research
> session can resume cold. Decisions land in a follow-up plan / ADR after
> the deep-sweep finishes.

## The framing

Traditional agile/scrum was built for **persistent humans across time**: standups exist because teammates need to coordinate, retrospectives because the same team carries lessons forward, sprint planning because the same backlog persists across sprints. ADR-0001 (agentic-homelab-practices) explicitly rejected the human-coordination practices on the grounds that they don't translate to a single-operator-plus-agents setup.

But the operator's observation surfaces a different lens: **agile's STRUCTURE is what's load-bearing, not its assumption of persistent humans.** Replace the "team" axis with "amnesiac sessions" and check which ceremonies still earn rent.

```
Traditional scrum                  Agentic-dev mapping (proposed)
─────────────────                  ──────────────────────────────
Product manager (persistent)       Operator (persistent — you)
Developer team (persistent)        Agent (fresh per session — amnesiac)
Sprint (time-boxed work)           Session (the agent's context window)
Sprint backlog                     The session's stated goals
PR / increment (deliverable)       The session's PR(s)
Sprint planning                    Session preamble — design + scope
Daily standup                      Subagent → main agent reporting?
Sprint review                      Operator-gated PR review
Retrospective                      End-of-session reflection
Product backlog                    docs/roadmap.md
Backlog grooming                   Roadmap maintenance
```

The wrinkle is the **bus factor: 100% per sprint**. Every developer leaves at session end. Knowledge transfer happens through docs, not through teammates carrying tacit context. This is ADR-0001's "amnesiac team" model, but applied at sprint granularity rather than just process-design granularity.

## Per-PR ceremony (operator's sketch)

Each PR (= one feature or in-depth improvement, not fixes) deserves its own:

| Phase | What | Operator-facing artifact |
|---|---|---|
| **Preamble** | Design + planning. State the goal, name the right answer first, capture decisions. | Brainstorming notes, a `docs/specs/` stub, or an ADR draft |
| **Execution** | The actual code/docs work. Commit-by-commit, surfacing diffs. | Commits on a branch |
| **Reporting** | What got done, what surfaced, what was deferred. | PR description + commit messages + linked `docs/reports/` |
| **Reflection** | What worked, what didn't, what to do differently next time. | Notes back to operator / memory entries / SKILL updates |

The execution phase has its own cadence; the planning + reporting + reflection are session-bookends.

## CI/CD reframed

The traditional ratio (remote CI heavy, local checks light) inverts under agentic dev:

```
Traditional dev                    Agentic dev
───────────────                    ───────────
Local: lightweight (lint)          Local: heavyweight (pre-commit hooks,
                                            git worktrees for isolation,
                                            `nix flake check`, agent
                                            shell-tool execution)
Remote: heavyweight (CI/CD)        Remote: backstop only (catches what
                                            local skipped)
```

The agent runs the heavy gates locally before pushing. CI's job becomes "the agent forgot or skipped" rather than "this is where things get checked."

## Subagent workflows as standups

Standups in human teams are status-reporting + coordination. In agentic dev, **subagents do the same thing implicitly** when they finish and return a summary to the main agent. The standup is the agent collaboration topology, not a meeting.

This generalises: the main agent is the scrum master + tech lead; subagents are workers reporting up; the operator is the PM doing periodic checks. Sprints don't need a daily standup because the topology already enforces reporting.

## Open research questions

Categorised by ceremony / artifact / role:

### Ceremonies — which translate, which don't?

| Scrum ceremony | Does it translate to agentic dev? |
|---|---|
| Sprint planning | Probably yes — session preamble + design pass |
| Daily standup | Probably no — subagent reporting handles it implicitly |
| Sprint review | Yes — operator-gated PR review |
| Retrospective | Yes — end-of-session reflection (skill/memory updates) |
| Backlog refinement | Yes — `docs/roadmap.md` upkeep |
| Story sizing / estimation | TBD — agents don't have velocity in the same sense |
| Mid-sprint course corrections | Yes — operator can redirect any turn |

### Artifacts — what shape per-agent?

| Scrum artifact | Agentic mapping (proposed) | Open Q |
|---|---|---|
| Product backlog | `docs/roadmap.md` | Already exists |
| Sprint backlog | Session preamble doc / opening message | Where does it persist? |
| Increment | The PR | PR-per-session vs PR-per-task |
| Definition of Done | `nix flake check` + operator review | Captured anywhere explicitly? |

### Role — the operator becomes…

- Product manager: scoping + acceptance criteria
- Tech lead: the bigger architectural decisions (mostly via ADRs)
- Scrum master: ensuring the ceremony actually happens
- Reviewer: PR review (the operator-gated push from `CLAUDE.md`)

Open: **which of these roles to formalise vs leave implicit?** Right now they're all bundled under "operator;" naming them might help the operator know which hat to wear when.

### Branching + PRs (ADR-0005 candidate)

The operator's proposal for local branching + PRs is the load-bearing structural change here. ADR-0001 explicitly rejected feature branches; the new argument is **operator cognitive load**, not multi-human coordination. Worth its own ADR before workflow changes.

Open questions:
- One PR per session, or PR-per-architectural-move within a session?
- Long-lived feature branches or short-lived per-feature?
- Worktrees for isolation vs branches in the same checkout?
- Auto-merge after operator ack, or manual?
- Per-PR template (preamble + reporting + reflection sections)?

### CI/CD specifics

- Pre-commit hook (already exists for `nix flake check` on `.nix` changes) — is the local gate sufficient?
- Worktree-per-PR for isolation — homelab has `using-git-worktrees` skill; how does it fit the agentic ceremony?
- Remote backstop — what does GitHub Actions catch that pre-commit misses?

## Seed observations to NOT lose

Operator's framing in the 2026-06-16 session:

1. **"I become the product manager."** The persistent role is operator-side; agents rotate. The PM hat is the load-bearing one.
2. **"A session becomes a sprint with a PR per."** PR is the deliverable unit; one per session (or per feature) is the natural granularity.
3. **"Per PR deserves its own preamble designing and planning phase, execution phase, reporting phase, and reflection for improvement."** The ceremony shape per PR.
4. **"Per session is also a new amnesiac software development team — the real wrinkle to traditional agile."** The bus-factor-100% wrinkle that drives doc-as-transmission-medium (ADR-0001).
5. **"CI/CD is still useful though it becomes less important remotely and more important locally through pre-commit hooks, git worktrees etc."** The CI inversion.
6. **"Standups are basically just subagent workflows reporting their work to the main agent."** The standup → topology mapping.

## When this becomes a plan

After `docs/plans/2026-06-16-docs-deep-sweep.md` wraps (phases 3a-3d + remaining 3b sweeps land). Then:

- Operator + agent session to walk the open questions and decide ceremony-by-ceremony
- Produce ADR-0005 (or similar) capturing the workflow shape
- Produce a `docs/plans/` entry for implementation if any tooling needs to land
- Update SKILL.md files (`wrap-session`, `wrap-feature`, etc.) to reflect chosen ceremonies

## Worked example — 2026-06-16 docs deep-sweep sprint retro

Captured because the spec predicted the reflection phase would surface
real misses, and it did. Concrete data for the research session;
N=1 but ceiling-of-confidence is higher than zero.

### Sprint shape
- **Scope:** Phase 3a + 3b + 3c of the docs deep-sweep plan
- **Deliverable:** 15 commits, +2577 / -1047, all CI green
- **Subagents used:** 1 (Phase 1 inventory Explore agent — the
  closest analog to a standup, returning a structured report)
- **Operator hat:** PM (scope) + reviewer (PR review at sprint end)
- **Agent hat:** scrum master + tech lead (execution + atomic commits)

### Ceremonies that organically happened
- **Preamble** — short: operator said "finish the docs thing first
  so content sweep", agent scoped 7 sub-sweeps from memory. Did NOT
  surface the punch list for confirmation before editing — caught in
  retro as a miss.
- **Execution** — atomic commits per sub-sweep, each with descriptive
  body listing "intentionally NOT touched" items.
- **Reporting** — at operator request: PR-review-style rundown of all
  15 commits, commit-by-commit grades, cross-cutting observations.
  Surfaced two pre-existing debt items + one missing trailer.
- **Reflection** — operator drove explicitly (this section). Four
  questions: keeps / DoD / changes / amnesiac handoff.

### Concrete misses surfaced by the retro
1. **No Definition of Done up front.** Plan file's Phase 4 was the
   plan-defined DoD; we shipped 3a/3b/3c but skipped Phase 4
   validation. Self-graded 4/7 of a sensible post-hoc DoD.
2. **Progress log table in the plan file was never updated mid-sprint.**
   Fixed in DoD-closure commit; would have been better to update per
   sub-phase as a self-imposed standup.
3. **One commit missing the `Co-Authored-By:` trailer.** Pre-commit
   hook doesn't catch trailers; either bake into hook or accept the
   occasional drop.
4. **TaskCreate not used despite 4 system reminders.** Self-imposed
   visibility gap for a wide-sweep sprint. The "main agent IS the
   scrum master" framing makes the agent-self-tracking the standup-
   equivalent; declining it leaves the operator without per-step state.
5. **No mid-sprint checkpoint discipline.** SOUL.md's "Knob — checkpoint
   cadence" axiom (restate done/verified/left) was honored only at the
   operator's explicit retro request.

### Things that worked, worth keeping
- **Plan persisted first** before any Phase 3 edit; Explore-agent
  inventory was cheap insurance.
- **Atomic per-axis commits** — bigger commits would have been faster
  to land but per-commit revert is the value.
- **"Intentionally NOT touched" lists** in commit bodies — prevents
  the next agent from "fixing" historical artifacts.
- **Catalog kills > catalog maintenance** — when the SoT axiom can be
  applied, drift-source eliminated by construction beats keeping prose
  in sync.
- **Promote-to-CI when possible** — the routing-coherence flake check
  (3a.5) is the prose → law promotion applied to docs structure itself.
- **PR-review-as-checkpoint** before push caught items that would have
  shipped silently.

### Codification call
Operator + agent agreed (this session): **defer skill codification**
to after ADR-0005 lands. SOUL.md "iterate-to-stable, then codify";
N=1 isn't stable; the research phase is exactly the iterate-to-stable
step. This worked example becomes one data point for that research,
not the answer to it.

## References

- `docs/decisions/0001-agentic-homelab-practices.md` — the ADR this work would revise (or extend); explicitly rejected feature branches on the "no humans to coordinate" axis. The new argument changes the axis.
- `docs/plans/2026-06-16-docs-deep-sweep.md` — parent plan; this research session waits for it to finish
- `docs/specs/2026-06-16-lint-rule-schema.md` — Phase 3d spec that triggered this meta-observation
- `home/claude-code/skills/wrap-session/SKILL.md` — existing end-of-session ceremony
- `home/claude-code/skills/wrap-feature/SKILL.md` — existing per-feature ceremony
- `home/claude-code/skills/brainstorming/SKILL.md` — existing preamble-shaped ceremony
- `home/claude-code/skills/dev-loop/SKILL.md` — the workflow map; will likely get a refresh after ADR-0005
