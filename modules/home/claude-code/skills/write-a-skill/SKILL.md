---
name: write-a-skill
description: Author or edit a Claude skill — gather what it must cover, draft a concise SKILL.md, then validate it against a fresh agent before deploying. Covers the frontmatter spec, when to split into supporting files, and how to test a skill proportionally to its type. Use when creating a new skill, editing an existing one, or when the user says "write a skill", "turn this into a skill", or "codify this workflow".
---

# Write a skill

A skill is a reusable reference guide for a proven technique or workflow — not a
narrative of how you solved something once. Keep it concise: a skill the next agent
won't read is useless.

## Phase 1 — Gather

Before drafting, settle:

- What task / domain does it cover, and what are the concrete triggers for using it?
- Which use cases must it handle? (and which it explicitly should _not_)
- Is it a **discipline** skill (enforces a rule under pressure), a **technique**
  (how-to), or a **reference** (lookup)? This sets how you test it (Phase 3).
- Does it need executable scripts or reference files, or is prose enough?

## Phase 2 — Draft

- One self-contained `SKILL.md` is the default. Keep it tight — aim under ~120 lines;
  if it's growing past that, that's a signal to split, not to keep piling on.
- Split into supporting files only for **heavy reference** (long API/syntax docs) or
  **reusable scripts/templates** — not to chop a normal skill into fragments.
- Lead with the core principle, then the procedure. Tables for lookups, numbered
  lists for linear steps, a small flowchart only for a non-obvious decision.

### Frontmatter (the spec — house standard)

```
---
name: skill-name              # letters/numbers/hyphens; matches the directory
description: <capability>. Use when <triggers>.
---
```

Two fields, `name` + `description` (agentskills.io spec; max 1024 chars). The
description is **capability + when-to-use triggers — never a step-by-step summary of
the workflow.** A description that summarizes the steps creates a shortcut: the agent
follows the blurb and skips the body. State what it's for and when to reach for it;
let the body carry the how.

> Do **not** invent extra frontmatter fields (e.g. `when_to_use`) — they're off-spec.
> Fold the triggers into `description`. (`analyse-system` still carries a stray
> `when_to_use` — clean it up when you next touch it.)

## Phase 3 — Validate against a fresh agent

Don't ship a skill you've only read. Test it proportionally to its type:

- **Discipline skill:** baseline-test first — give a fresh subagent a realistic task
  **without** the skill and watch what it does wrong (the RED). Then give a fresh
  agent the same task **with** the skill and confirm the behavior changes (the GREEN).
  Prefer an **inspectable artifact** over self-report — e.g. have it commit per step
  and read the git log, rather than trusting "I did it test-first."
- **Technique skill:** an application scenario — hand it a fresh agent on a realistic
  case and check it applies the technique correctly (catches the planted issue, makes
  the right first move).
- **Reference skill:** a retrieval scenario — can the agent find and correctly use the
  right piece?

Then **fold the friction back in.** The dry-run almost always surfaces gaps (an
unhandled bootstrap case, an autonomous-vs-interactive assumption, a proportionality
nudge). Edit the skill to close them — that's the refactor leg of writing a skill.
Match test rigor to stakes: a small reference skill doesn't need a pressure test.

## Phase 4 — Review with the user, then deploy

Show the draft + the validation result. Confirm it covers the cases and reads
cleanly, then commit (small, why-focused). Don't batch-create untested skills.

## Anti-patterns

- Narrative ("in session X we found…") instead of a reusable guide.
- Workflow summary in the `description` (the agent skips the body).
- Multi-language dilution — one excellent example beats five mediocre ones.
- Splitting a normal-sized skill across files for no reason.
- Shipping without watching a fresh agent use it.
