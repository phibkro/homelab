---
name: improve-codebase-architecture
description: Surface architectural friction and propose deepening opportunities — shallow modules, leaky seams, testability gaps — using the project's domain language and a consistent Module / Interface / Depth / Seam / Adapter vocabulary, grounded in locality and leverage. Use when reviewing structure, when a module feels shallow or tangled, when debugging keeps revealing coupling (handed off from `diagnose`), or when the user asks to improve the architecture.
---

# Improve codebase architecture

Find where the structure fights the people working in it, and propose changes that
turn shallow, brittle modules into deep, maintainable ones.

**Core idea — depth is leverage.** A good module hides substantial behaviour behind a
small interface: callers get a lot, learn a little. Judge candidates by two measures:

- **Locality** — is the knowledge to understand this concentrated in one place, or
  smeared across many files you must hold in your head at once?
- **Leverage** — does the caller benefit from the depth, or does the interface expose
  as much complexity as the implementation (a pass-through that earns nothing)?

Speak in a consistent vocabulary: **module, interface, implementation, depth, seam,
adapter.** The interface is the test surface.

## Informed by the domain — read first

Read the project's glossary / source-of-truth docs (`CONTEXT.md`, `CONCEPTS.md`) and
any ADRs **before** walking the code. The domain language names good seams; the ADRs
record decisions you must **not** re-litigate. Naming a deepened module after a
concept not yet in the glossary? Add the term as you go.

## Phase 1 — Explore

Walk the code organically and note friction:

- **Shallow modules** — interface nearly as wide as the implementation.
- **Tangled seams** — understanding bounces across many files; change here forces
  change there.
- **Testability gaps** — the real logic can't be tested because it's fused to I/O, so
  tests live in the caller and can't catch the bug.

Apply the **deletion test**: would removing this module *concentrate* its complexity
(good — it was a false pass-through) or *scatter* it (it was earning its keep)? False
pass-throughs are deepening opportunities.

## Phase 2 — Present candidates

Present each candidate concisely — before/after sketch, which files are involved, why
the current shape causes friction, what changes, and how testability/clarity improve.
Use the shared vocabulary; reference the glossary for domain concepts. Mark any
candidate that **conflicts with an existing ADR** explicitly — only reopen a settled
decision when the friction genuinely justifies it.

(Keep this lightweight — a tight before/after in prose or a small diagram. Don't build
elaborate report tooling; the candidates are the point.)

## Phase 3 — Grilling loop

Pick one candidate with the user and walk its design tree together (this is where
`grill-with-docs` applies). As new concepts crystallize, update `CONTEXT.md` lazily.
Record a rejection as an **ADR only when** it's hard to reverse AND surprising AND a
real trade-off — so the same idea isn't re-proposed later. Most outcomes are a doc
line, not an ADR.

## The deepening moves (this project's grain)

- **Functional core / imperative shell is a seam.** A deep module is often a pure core
  (decision logic, no effects) behind a small interface, with effects pushed to the
  edges. Marking the boundary (`// pure:` / `// effects:`) makes the seam legible and
  the pure core testable by law.
- **Ports & adapters.** A port is the small stable interface; adapters are the
  swappable implementations behind it. Good seams are ports — new providers, new
  frontends, new tools slot in as adapters without touching the core.
- **Barrels for depth.** A multi-file module exposes one entry point (`index.ts`);
  callers import the concept, not the internals.
- **Composition over inheritance.** Build depth by composing values, not class trees —
  hierarchy should emerge from composition.
- **Enumerable blast radius.** Prefer structures where the effect/security surface gets
  *easier* to enumerate as depth increases, not buried.

## Proportionality

Don't deepen what doesn't need it. A small pure function is complete as it is; a class
tree for a lookup table is over-architecture. The goal is the structure a senior reader
would call right-sized — neither shallow-and-scattered nor deep-for-its-own-sake.
