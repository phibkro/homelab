---
name: tdd
description: Test-driven development through a goal-driven red-green-refactor loop that builds deep modules and verifies behavior through public interfaces. Use when implementing a feature or fixing a bug, before writing implementation code, or when the user mentions TDD, red-green-refactor, test-first, or "write the test first". Not for throwaway prototypes, generated code, or config files — name that exception out loud rather than rationalizing into it.
---

# Test-Driven Development

Write the test first. Watch it fail. Write minimal code to pass. Refactor.

**Core principle:** if you didn't watch the test fail, you don't know it tests the
right thing. Tests verify behavior through public interfaces — code can change
entirely; tests shouldn't.

## Start with the goal, not the steps

Before any code, state the **success criteria** — the observable conditions that
mean "done." Strong criteria let you loop independently without checking in at
every step. Then confirm the shape of the work with your human partner:

- What should the **public interface** look like? (the test surface)
- Which **behaviors** matter most to test? You can't test everything — prioritize
  critical paths and complex logic, not every edge case.
- Where are the **deep-module** opportunities (small interface, deep implementation)?
- List the **behaviors to test** — not implementation steps. Get approval.

This is the planning gate. It replaces a heavyweight plan: a goal + a prioritized
behavior list is enough to loop. Running autonomously with no partner to approve?
State the success criteria and behavior list explicitly, then proceed — the
criteria are your gate.

## The loop

```
RED  →  verify it fails  →  GREEN  →  verify it passes  →  REFACTOR  →  next
```

### RED — write one failing test

One behavior. A name that reads like a spec ("retries a failed operation 3 times").
Real code paths through the public interface — no mocks unless genuinely unavoidable.

### Verify RED — watch it fail (MANDATORY, never skip)

Run the test. Confirm it **fails** (not errors), and fails for the **expected
reason** (feature missing, not a typo or import error).

- Passes already? You're testing existing behavior — fix the test.
- Errors instead of failing? Fix the error, re-run until it fails cleanly.
- First slice (tracer bullet)? A missing module/import is an unavoidable type
  error, not a clean failure. Add the smallest stub (an empty export, or a
  deliberately wrong return) so the test fails on the **assertion** — that's your
  real RED.

Skipping this step is the single most common way to end up with a test that proves
nothing. A test you never saw fail is not a test yet.

### GREEN — minimal code

The simplest code that passes *this* test. Don't anticipate future tests, don't add
options "while you're here." Confirm the test passes and **no other test broke** and
output is pristine (no stray warnings).

### REFACTOR — only once green

Never refactor while red — get to green first. Then:

- Extract duplication; improve names.
- **Deepen modules** — move complexity behind a small interface (see below).
- **Separate pure from effectful** — pull side-effect-free logic out of I/O so it's
  testable without mocks (functional core, imperative shell).
- Consider what the new code reveals about existing code.
- Run the tests after each refactor step; stay green throughout.

## Vertical slices, not horizontal

**Do NOT write all the tests first, then all the implementation.** That tests
*imagined* behavior — you commit to test shape before you understand the code, and
the tests go insensitive to real changes (pass when behavior breaks).

```
WRONG (horizontal):  test1,test2,test3  then  impl1,impl2,impl3
RIGHT (vertical):    test1→impl1 → test2→impl2 → test3→impl3
```

One test → one implementation → repeat. The first slice is a **tracer bullet**: the
simplest behavior, proving the path works end to end. Each later test responds to
what the previous slice taught you.

## Deep modules + functional-core/imperative-shell

The refactor leg is where architecture happens. Two opinions guide it:

- **Deep modules:** a good module hides a lot of implementation behind a small
  interface. Depth = leverage: callers get a lot, learn a little. A module whose
  interface is as wide as its implementation (a pass-through) earns nothing — apply
  the deletion test: would removing it concentrate complexity, or just scatter it?
- **Functional core, imperative shell:** keep decision logic pure (no I/O, no
  effects) and push effects to the edges. Mark the boundary explicitly (e.g. a
  `// pure:` / `// effects:` header) so the next reader sees it. Pure cores are
  tested by law (unit/property tests, correct by construction); the effectful shell
  is tested against the real thing, not mocks.

A module exposing many internal files should present one entry point (a barrel) and
let callers import the concept, not the internals.

**Match the architecture to the problem.** Don't deepen what doesn't need it — a
small pure function is complete as it is. Over-architecting trivial code (a class
tree for a lookup table) is its own smell; a senior reader should never call the
result overcomplicated.

## When stuck

| Problem | Move |
|---|---|
| Don't know how to test it | Write the wished-for API first; write the assertion first. |
| Test is hard to write | The design is hard to use. Simplify the interface. |
| Must mock everything | Code is too coupled — separate pure logic from effects, inject dependencies. |
| Genuinely blocked | Research the design (read references, working examples) or reach out to your human partner. Don't thrash. |

## Per-cycle checklist

- [ ] Test describes behavior, not implementation
- [ ] Test uses the public interface only — would survive an internal refactor
- [ ] Watched it fail, for the expected reason
- [ ] Code is minimal for this test; nothing speculative
- [ ] All tests green, output pristine
- [ ] Refactored toward depth / pure-effect separation while staying green

## The iron rule

```
Production code → a test exists and failed first.
Otherwise → it isn't TDD.
```

Wrote code before the test? Delete it and start fresh from the test — don't "adapt"
it while writing the test; that's just testing after. The exception (prototypes,
generated code, config) is real but rare — name it explicitly, don't rationalize
into it.
