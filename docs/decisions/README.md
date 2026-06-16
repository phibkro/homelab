---
summary: ADR (Architecture Decision Record) conventions for the homelab — when to write one, file shape, numbering, status lifecycle.
---

# Architecture Decision Records (ADRs)

Dated, statused records of **hard-to-reverse decisions** for the homelab — choices a future agent (or future-you) will want the *why* for. Routine choices live in commit messages; ADRs carry the heavier decisions commits can't fit.

## When to write one

Write an ADR when:

- The decision is non-obvious and someone will ask "why" later.
- Alternatives were considered and rejected on substantive grounds.
- Reversing the choice would require coordinated changes across multiple modules/hosts.
- A current convention is being changed (an ADR can supersede a previous ADR).

Don't write an ADR for:

- Routine implementation choices (commit message is enough).
- Patterns already documented in `docs/reference/module-authoring.md` / `docs/reference/enforcement.md` (just follow the convention).
- Tactical landmines (`.claude/skills/gotcha-*/` is the right home — one skill per landmine).
- Load-bearing claims (`docs/invariants.md` carries those with their enforcement tier).

## File shape

```markdown
# ADR-NNNN: <one-line title>

- Status: Proposed | Accepted | Superseded by ADR-XXXX | Deprecated
- Date: YYYY-MM-DD

## Context

What's the situation that makes this a decision worth recording?

## Decision

What we picked. State plainly, no hedging.

## Consequences

What this enables, what it constrains, what becomes structurally
enforced, what now requires another ADR to change.

## Alternatives considered (optional)

What else was on the table and why it lost. Skip if there were no
serious alternatives.
```

Naming: `NNNN-kebab-case-title.md`, four-digit zero-padded sequential.

## Status lifecycle

- **Proposed** — drafted, not yet adopted. Keeps the decision visible while it's being worked through.
- **Accepted** — in force. Default after the operator OK's the draft.
- **Superseded by ADR-XXXX** — the original stays; the new ADR explains why. Don't delete superseded ADRs; they record the path.
- **Deprecated** — was accepted, now obsolete, no replacement (the practice just stopped). Rare.

## Index

The decisions in this directory **are** the index — chronological by number. List with `ls docs/decisions/*.md`.
