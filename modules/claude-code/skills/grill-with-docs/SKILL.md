---
name: grill-with-docs
description: Stress-tests a draft design or plan against the project's domain language, documentation, and code reality through relentless one-at-a-time interrogation — surfacing terminology conflicts, sharpening vague terms into canonical ones, checking the design against what the code actually does, and updating the docs inline as decisions resolve. Use when you have a rough design or plan to harden before implementing, when terminology feels fuzzy or contested, after brainstorming and before writing tests, or when the user says "grill this", "poke holes", or "is this design sound".
---

# Grill the design against the docs

A design isn't ready until its terms match the project's domain language and the
codebase actually does what the design assumes. This skill is the convergent half
of the loop: after ideas are generated, interrogate them until you and your human
partner share a precise understanding — then hand a hardened plan to TDD.

**Core principle:** code is the source of truth; docs are an approximation. Grill
both — sharpen the docs, and check the design against the code. When code and docs
disagree, that gap is itself a finding: the code is what's true _now_, the docs are
what was _intended_ — decide whether the doc is stale (update it) or the code drifted
from intent (a bug to log).

## Before you start — read the domain source of truth

Read these first so you interrogate in the project's own language, not generic terms:

- The **design source of truth** (e.g. `CONTEXT.md`) — rationale, constraints, the
  decisions already made.
- The **glossary / mental-models doc** (e.g. `docs/CONCEPTS.md`) — the canonical
  nouns and verbs.
- Any **decision log / ADRs** — settled trade-offs you must **not** re-litigate.
  (No decision log yet? Then nothing is closed — proceed.)

The glossary names good seams; the decision log records what's closed. If you don't
know why something is structured the way it is, that's a question, not an assumption.

## The loop — interrogate one question at a time

Ask relentlessly, **one question per turn**, and wait for the answer before the next.
The goal is shared, precise understanding — not running down a checklist. Stop when
confused and name exactly what's unclear; don't paper over it.

Use whichever of these moves the moment calls for:

1. **Domain-aware challenge.** The user's term conflicts with the glossary? Surface
   it immediately: "`CONTEXT.md` defines _cancellation_ as X, but you're using it as
   Y — which is it?"
2. **Precision refinement.** Replace vague language with the canonical term. "You
   said _account_ — is that a Customer or a User?"
3. **Scenario stress test.** Invent edge-case scenarios that probe a concept's
   boundary and force clarity on how things relate. "What happens to an in-flight
   approval when the session is forked?"
4. **Code-reality alignment.** When the user describes how something works, verify
   the codebase actually does that — read the code. Surface contradictions plainly:
   "Your design cancels the whole run, but the code cancels per-turn — which is real?"
5. **Surface conflicts, don't average them.** If two patterns or terms contradict,
   name the contradiction and **pick one** (the more recent / more tested), explain
   why, and flag the other for cleanup. Never blend conflicting patterns into a mushy
   middle.

## Update the docs inline, as decisions resolve

A resolved term or decision updates the docs **immediately**, not in a batch at the
end — an undocumented rule looks like a bug to the next reader. _Resolved_ means your
partner confirmed it — make the edit then, not while the question is still open.

- Resolved term / sharpened concept → update the glossary / `CONTEXT.md` now.
- A decision worth recording as an **ADR (or a dedicated decision entry in your
  project's decision log)** — but **only** when it is _all three_: hard to reverse,
  surprising without context, and the result of a real trade-off. Most resolutions
  are just glossary/`CONTEXT.md` edits, not ADRs. Don't manufacture ceremony.

## Done when

- The plan's terms are canonical (match the glossary, or the glossary now matches).
- The design is consistent with what the code actually does.
- Contradictions are resolved by choosing, not averaging.
- The docs reflect what you decided.

Then the plan is hardened — hand it to `tdd` to implement.
