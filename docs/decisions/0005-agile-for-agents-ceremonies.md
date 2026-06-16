# ADR-0005: Agile-for-agents ceremonies — per-PR preamble / execution / reporting / reflection

- Status: Accepted
- Date: 2026-06-16
- Refines: ADR-0001 (practices filter) — within the surviving set, decides ceremony shape
- Supersedes-in-part: ADR-0001 § "Feature branches / GitFlow" — re-litigated on the operator-cognitive-load axis (conclusion is unchanged but the reasoning is now nuanced)

## Context

ADR-0001 named the filter: *a software-team practice transfers iff it externalizes knowledge or verifies a claim*. It applied the filter to high-level practices (heavy docs ✓, conventional commits ✓, skills ✓, flake checks ✓; feature branches ✗, code review-as-gate ✗, onboarding meetings ✗).

What ADR-0001 didn't decide: WITHIN the surviving set, what shape does each practice take in an agentic context? The 2026-06-16 docs deep-sweep + retro forced the question. The operator's framing (`docs/specs/2026-06-16-agentic-development-workflow.md`) sketched six observations:

1. *"I become the product manager"* — operator role is persistent
2. *"A session becomes a sprint with a PR per"* — corrected by `[[session-economics]]` memory: session and PR decoupled
3. *"Per PR deserves its own preamble + execution + reporting + reflection"* — the ceremony shape
4. *"Per session is also a new amnesiac software development team"* — the wrinkle
5. *"CI/CD is still useful but the local/remote ratio inverts"* — heavy local, light remote backstop
6. *"Standups are basically just subagent workflows"* — standup → topology mapping

External practice (Spec-Driven Development's phase-boundary review, Scrum.org's AI-augmented retrospective writing, BMAD framework) independently converges on the same shape. Per-PR retrospective specifically is not well-documented in the wild — the framing is genuinely novel.

The 2026-06-16 retro itself surfaced concrete misses (no preamble confirmation, no DoD up front, plan progress log empty, one missing commit trailer, no mid-sprint checkpoints) that the ceremony adoption is meant to prevent next sprint.

## Decision

**The unit of agentic-dev work is the PR** (one feature or in-depth improvement, not a fix). Sessions and PRs are decoupled — see [[session-economics]] memory.

**Per-PR ceremony (four phases):**

```
Preamble  →  Execution  →  Reporting  →  Reflection
```

Detailed shape: `docs/reference/agentic-workflow.md`. The reference doc is the working how-to; this ADR is the decision record.

**Ceremony-by-ceremony adoption:**

| Scrum ceremony | Verdict | Maps to |
|---|---|---|
| Sprint planning | ADOPT | Preamble (Phase 1) |
| Daily standup | SKIP (implicit via topology) | Subagent reports + agent self-tracking |
| Sprint review | ADOPT | Reporting (Phase 3) |
| Retrospective | ADOPT (per-PR, not per-session) | Reflection (Phase 4) |
| Backlog refinement | ALREADY EXISTS | `docs/roadmap.md` |
| Story sizing / estimation | SKIP | No meaningful velocity; session-economics handles "fits in budget" |
| Mid-sprint course correction | ADOPT (always-available) | Operator can redirect any turn |

**Operator-role hats** (informational, not enforced): PM (scope), Tech lead (architecture), Scrum master (ensures ceremony), Reviewer (push gate). Same person, four hats.

**Branching:** commits-on-`main` stays the default; worktrees reserved for non-routine refactors (unchanged from ADR-0001 + existing CLAUDE.md). GitHub-style PRs not used — the PR-as-Reporting ceremony happens in-session before push.

**CI/CD inversion** (recording the rationale, no change to current state): heavy local (`nix flake check` + pre-commit), light remote (GitHub Actions as backstop).

**Hard-constraint vs soft-constraint split:** static checks are reserved for invariants that must hold every turn (commit subject grammar, type system, schema validation). Soft constraints (commit body quality, prose tone, comment depth) are caught in PR review (Phase 3 above) + prompting — false positives + brittleness dominate any static check on prose. Same principle as `docs/invariants.md` § "When to add a rule" applied to commit hygiene.

One concrete addition landing with this ADR: **`.githooks/commit-msg` enforces Conventional Commits v1.0.0** on the subject line. Hand-rolled bash (not commitlint) per ADR-0001 dep-preference (a reliable dep already in the tree beats hand-rolling — bash is in the closure; Node + Husky aren't). Pinned to spec v1.0.0; escalation path is `nix shell nixpkgs#commitlint-rs` if the regex outgrows itself. Allowed types: standard conventional set + homelab-specific `plan`, `spec`, `skill`. Scope chars match existing repo idioms including `+` for multi-scope. Bypass via `git commit --no-verify`.

The originally-proposed `Co-Authored-By:` trailer check is dropped — it's data-harvest cosmetic for the upstream model provider, not an invariant the operator values for the codebase.

## Consequences

**Process changes:**

- **Preamble becomes mandatory.** Agent surfaces goal + punch list + open questions + DoD before any tool call lands. Operator confirms or redirects. Skipping was the most-cited miss in the 2026-06-16 retro.
- **Reflection becomes mandatory at PR-end** (not session-end). The four questions are: keeps / DoD / changes / amnesiac-handoff. Operator-driven; agent answers honestly.
- **Plan files are maintained mid-sprint**, not at end. Progress-log entries land per sub-phase as a self-imposed standup-equivalent.
- **Debt named in tree wherever a fresh agent will find it**: plan files' "known debt" sections, `docs/roadmap.md` "architectural debt", or tagged TODOs. Not just in conversation.

**Tooling changes:**

- **`.githooks/commit-msg` lands with this ADR:** Conventional Commits v1.0.0 subject-line check on every commit. Hand-rolled bash, pinned to spec v1.0.0.
- **CLAUDE.md gains a § Agentic workflow** overview block pointing at `docs/reference/agentic-workflow.md`. Interface-only summary; deep impl lives in the reference doc. Same shape as the existing CLAUDE.md routing tables.

**Skill changes deferred:**

- **No per-pr-preamble or per-pr-reflection skill yet.** Rule of three; the 2026-06-16 sprint is N=1. Skills get extracted after 2-3 more sprints validate the ceremony shape. For now operator + agent walk it conversationally.
- **Existing skills (`wrap-session`, `wrap-feature`, `brainstorming`, `dev-loop`) get reviewed against this ADR** in a follow-up; some overlap with the new ceremonies and need either refresh or retirement.

**Spec lifecycle:**

- `docs/specs/2026-06-16-agentic-development-workflow.md` keeps its worked-example appendix (real data, useful to future readers) but frontmatter `status:` updates to "graduated to ADR-0005". The spec is no longer the SoT; the ADR + reference doc are.

## Alternatives considered

- **Codify ceremonies as skills now.** Rejected: N=1, SOUL.md "iterate-to-stable, then codify". The 2026-06-16 retro is the only data point; codifying prematurely bakes in this sprint's specific shape.
- **Meta-ADR + per-ceremony sub-ADRs.** Rejected: over-engineering. ADR-0001 already bundles practices into one ADR with consequences; following the precedent. If a specific ceremony decision needs revisiting later, that's a new ADR superseding the relevant section.
- **Per-session ceremonies instead of per-PR.** Rejected: per [[session-economics]] memory, sessions are context-budget-bounded not deliverable-bounded. PR is the better unit — it's the deliverable, and one PR can span multiple sessions or share a session with others.
- **Adopt BMAD framework's 21-agent + 50-workflow model.** Rejected: BMAD presumes team-of-agents shape (multiple specialized agents coordinating); the homelab has one agent + one operator. The scaffolding doesn't fit.
- **Adopt full Spec-Driven Development (SDD) framing** (machine-readable formal specs as primary artifact). Partial-adopt: SDD's phase-boundary review IS the preamble pattern. We don't adopt the full machine-readable-spec framing because most PRs are too small to justify it; the `docs/specs/` folder is for design-grade specs only.

## Related

- ADR-0001 — agentic homelab practices (the filter); this ADR refines it for within-the-filter ceremony shape
- `docs/reference/agentic-workflow.md` — the working reference doc; deep impl of every decision here
- `docs/specs/2026-06-16-agentic-development-workflow.md` — research seed with worked-example appendix; the 2026-06-16 sprint retro is the N=1 data point
- [[session-economics]] — the context-budget rule that decouples session from PR
- `docs/plans/2026-06-16-docs-deep-sweep.md` — the sprint that produced the worked example
