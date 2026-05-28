---
name: dev-loop
description: The one-page map of how development work flows and how to route yourself through it — triage, mode, research, then the right-depth phase chain (each phase its own skill). Use at the start of any non-trivial task, when unsure whether something needs a design phase, or when a fresh agent needs the whole workflow at a glance.
---

# dev-loop — the development workflow, one page

The spine every piece of work follows. This page **orients and routes**: it names
the phases and how to choose your path; each phase's *how* lives in its own skill.
Decide your path here, then open phase skills **on demand** — progressive
disclosure, don't pull a phase's detail into context until you're in it. Project
specifics (conventions, invariants) live in `AGENTS.md` / `CONTEXT.md`; this skill
is the general method that points into them.

```
triage → explore → [design] → implement (red-green) → wrap → iterate
```

Core principle: smallest correct slice, iterate to stable, verify live, commit small.

## Step 0 — Triage: should we even do this?

Before any work, decide and say which:

- **Go** — worth doing, in scope, aligned with the project's goals + invariants.
- **Push back** — wrong idea, or it tensions a value/invariant. Say so and propose
  the better thing. The cheapest win is not building the wrong thing.
- **Defer** — fine but out of scope now. Capture it (backlog / memory) and move on.

Check against the project's goals and invariants. This is the step most often
skipped and most often regretted.

## Step 1 — Classify the mode (sticky for the whole task)

| ask                                                | feature | issue / task |
| -------------------------------------------------- | ------- | ------------ |
| Introduces or reshapes an **abstraction**?         | yes     | no           |
| Must fit new **concepts / paradigms**?             | yes     | no           |
| "Solve within what already exists"?                | no      | yes          |

**Feature** → needs a design phase. **Issue / task** → skip design; solve and match
conventions. Mode is **sticky** — decided once, carried through. A phase may
*escalate* an issue to feature if real abstraction work surfaces — the exception,
not the default.

## Step 2 — Explore (research-first, both modes)

Look up the **state of the art** for this *shape* of problem from reliable sources
**first**, then match the implementation to this codebase's conventions. Don't jump
straight to local invention.

## Route — follow the chain for your mode

**Feature:** `brainstorming` (problem / solution / abstraction design) →
`grill-with-docs` (harden the design against code + docs) → `tdd` (red-green,
vertical slices) → `wrap-feature`.

**Issue / task:** (a bug? → `diagnose` first) → `tdd` → light wrap
(`wrap-session`). No brainstorm, no abstraction design.

Open each named skill when you reach that phase — not before.

## Always on (pointers, not copies)

- **TDD iron rule:** production code only after a test failed first; watch it fail.
- **Choose the test level** — example / property / integration / e2e (see `tdd`).
- **Security & values gate everything** — the project's invariants; surface
  tradeoffs rather than quietly trading them away.
- **Commit small**, why-focused messages.

## Done when

The success criteria — stated up front — are met and **verified live**: not just
"tests pass" but feature-correct, checked against the real thing.
