---
name: wrap-feature
description: Close out a finished feature or slice so it leaves no stale artifacts — confirm the success criteria are actually met and the suite is green, update the docs the change touched, record any design decisions worth keeping, and log what was intentionally deferred. Use when a feature, slice, or task is complete and before moving to the next one — "wrap up this feature", "finish this off", "is this done", or right after the last test goes green.
---

# Feature wrap-up

A feature isn't done when the code works — it's done when the next reader can't tell
you were ever confused: the docs match reality, the decisions are recorded, and what
you left undone is named out loud. This fires per feature (possibly mid-session),
distinct from `wrap-session` (which handles push + handoff at session end). If the
session is also ending, do this first, then hand to `wrap-session`.

## Procedure

### 1. Confirm the goal is actually met

- Re-read the **success criteria** you set at the start (the `tdd` planning gate).
  Each one observably satisfied? If not, you're not wrapping up — keep going.
- Run the full suite / CI, not just the tests you touched. **Fail loud:** "done" is
  wrong if anything was skipped silently; "green" is wrong if any test was skipped.
  Report the actual result.

### 2. Update the docs the change touched

Only the docs this feature actually affected — surgical, not a doc sweep:

- **Usage** (`README`) — new flags, commands, or surfaces the user now has.
- **Source of truth** (`CONTEXT.md` / design doc) — move the item from backlog →
  shipped, update what's next, refresh the architecture map if a new
  module/seam/adapter landed.
- **Glossary** (`CONCEPTS.md`) — any new canonical noun/verb the feature introduced.

### 3. Record design decisions worth keeping

- **Surface intended behavior.** Precedence, defaults, fallbacks, shadowing, merge
  rules decided in the code are documented as _intended_ — an undocumented rule looks
  like a bug to the next reader.
- **ADR / decision-log entry only when** the decision is _all three_: hard to reverse,
  surprising without context, and a real trade-off (same test as `grill-with-docs`).
  Most decisions are just a doc line, not an ADR. Don't manufacture ceremony.

### 4. Log what was deferred

Name the loose ends explicitly so they aren't silently lost:

- Intentionally deferred scope — **with the why** (and, if known, the condition or
  date that would trigger it).
- TODOs / follow-ups the feature surfaced.
- Be honest about the line between _done_ and _deferred_ — don't let "mostly done"
  read as "done".

### 5. Commit

Small, focused commit(s) with a **why-focused** body (Conventional Commits). The diff
shows what changed; the message explains why it mattered.

## Done when

The criteria are verifiably met, the suite is green (and you said so plainly), the
touched docs match reality, durable decisions are recorded, and the deferred items
are written down rather than carried only in your head.
