---
name: refactor
description: Scan a small, recent diff for Single-Source-of-Truth violations (duplicated literals, cross-file/cross-language duplicated facts, copy-pasted logic, stale comments) and Correct-by-Construction opportunities (runtime checks that could become structural guarantees), then recommend a fix using the generate > test > convention ladder. Use as the refactor step in red -> green -> refactor, right after a change goes green and before calling it done — scoped to what was just touched, not a whole-repo sweep. Single-pass, no subagents.
---

# Refactor: SSOT + Correct-by-Construction scan

Reach for this right after tests go green, before moving on — the refactor step of
red → green → refactor. Scoped to the diff you just produced, not a repo sweep (that's
`/simplify` or `/code-review`'s job). Read the diff, reason inline, apply the
straightforward fixes directly. No subagents — this should be fast enough to run every
loop.

## The two lenses

**Single Source of Truth** — has the same fact been typed twice? A literal string, a
list of names, a query/transform pipeline, a config value — if two places encode the
same fact independently, they can drift (the classic "update anomaly").

**Correct by Construction** — could an "illegal state" this code guards with a runtime
check instead be made *unrepresentable* by the data's own shape? Rarer to find than SSOT
violations in ordinary application code, but worth one pass: look for an `if` guarding a
case a tighter type or different data shape would rule out entirely.

## Scan checklist — walk all 5, not just the obvious hits

Duplication jumps out; staleness doesn't — it takes a deliberate second look, since
finding it means checking a claim against reality rather than pattern-matching repeated
text. Don't stop once 1–3 turn up something; item 4 needs its own dedicated pass.

1. **Repeated literals** — the same string/number/key at 2+ call sites → collapse into
   one named constant.
2. **Repeated facts across files or languages** — the same data (a list, a name, a
   config value) hand-typed independently in more than one place → generate one from
   the other, or both from a shared source.
3. **Repeated logic/pipelines** — the same sequence of operations copy-pasted →
   extract once. When extracting, separate **query** (reads, returns data, no side
   effect) from **command** (does something) — don't let one function do both if the
   duplicated shape is actually two different responsibilities.
4. **Stale comments/docs** — for every comment touching the diff, ask explicitly: does
   the code below it *actually still do this*? Don't just read the comment for
   plausibility — trace the one claim it makes against the code. A comment describing
   behavior that was removed, or was never implemented, is a correctness bug, not a
   style nit.
5. **Runtime checks that could be structural** — a conditional guarding a state that a
   tighter type, a different shape, or removing an option would make impossible
   instead of checked.

## Deciding the fix: the ladder

For each hit, reach for the highest rung that's actually proportionate:

| Rung | What it means | Reach for this when |
|---|---|---|
| **generate** | Derive one artifact from the other; drift becomes unrepresentable | Default target — the generation mechanism is cheap relative to what's already in the codebase (same language, or a build step that already exists) |
| **test** | A check that fails when the copies diverge | Generation would need machinery disproportionate to the risk (e.g. exposing a new public interface just to satisfy one consumer) |
| **convention** | Hand-discipline, a comment noting the duplication | Last resort — and named explicitly as a costed decision, not left silent. State what a real fix would need and why it's not worth it now. **Genuinely separate repos/deploy pipelines with no shared package** is a first-class reason to land here, not a fallback for laziness — say that's the reason, not just "kept in sync by hand." |

Descending the ladder is always a stated decision, never a default. Landing on
"convention" without saying why is indistinguishable from not having scanned at all.

## Output shape

For each finding: **what's duplicated or checkable**, **where** (every copy, file:line),
**which rung** and why. Apply the mechanical ones directly — changing *how* a public
name is populated (e.g. one file now imports another's list instead of retyping it) is
mechanical as long as the name, type, and values it exposes don't change. Propose and
ask first for anything that changes a public name, type, or shape itself (e.g. strings
→ an enum) — that's a design call even when it's the more correct fix.

## Anti-pattern

Don't mechanically force every finding to "generate." A disproportionate generation
mechanism — e.g. promoting a private value to a whole new exposed option just to
satisfy one test file — is worse than an honestly-named convention-level exception.
Judge proportionality; don't climb the ladder reflexively.
