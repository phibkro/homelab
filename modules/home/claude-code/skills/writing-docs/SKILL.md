---
name: writing-docs
description: Write and restructure agent-facing documentation (CLAUDE.md, AGENTS.md, READMEs, specs, ADRs, design docs, skills, memory) so a fresh reader finds the right claim fast and trusts it — precise, concise, visual (mermaid/tables/lists/arrows), and organised by progressive disclosure. Use when authoring or reviewing any doc an agent will read, when a doc reads like a wall of text, when onboarding docs for a fresh agent, or when the user says "write docs", "document this", "clean up these docs", or "is this doc clear". Not for end-user/marketing copy or generated API reference.
---

# Writing agent-facing docs

**Core principle.** The reader is an agent with no memory and a token budget.
Optimise for **retrieval, not narration**: the right reader finds the right claim
fast, trusts it (it's bound to evidence), and never reads what they don't need.

Four levers — fail any one and the doc rots:

| Lever | Means | Failure smell |
| --- | --- | --- |
| **Progressive disclosure** | tiered docs; an index routes, detail drills down | one fat doc; deep detail injected every turn |
| **Concise** | reference, not story; density over prose | wall of text; narrative ("in session X…") |
| **Visual** | the shape matches the content | enumerable facts buried in paragraphs |
| **Precise** | claims bound to evidence | "is enforced" with nothing enforcing it |

## Progressive disclosure — one job per doc, tier by purpose

Cross-reference, never duplicate (two copies drift). An **index doc** routes ("read
the one you need, not all"); each doc **self-describes** with a `summary` line + a
section map, so relevance is decidable without reading the body.

| Tier | Holds | Read when |
| --- | --- | --- |
| **0 entrypoint** — injected (CLAUDE.md / AGENTS.md) | how-we-work · docs-map · definition-of-done | always, first — keep it LEAN |
| **1 what / why** — context, roadmap | durable design · forward plan | starting a task |
| **2 reference** — concepts, invariants, architecture, ADRs | glossary · load-bearing claims · where-things-live | on demand / before re-litigating |
| **3 drill-down** — specs | deep per-feature design | implementing that feature |

The injected-every-turn file is the scarcest real estate: push detail down a tier
and link to it. Token budget is the whole reason tiers exist.

## Visual — match the shape to the content

| Content shape | Use |
| --- | --- |
| enumerable set / comparison | **table** |
| linear procedure | **numbered list** |
| flow · state machine · pipeline | **mermaid** + a one-line legend; colour-code with `classDef` |
| relationship · exit · causation | **arrows** → ⇒ (dotted for exits/failure) |
| parallel facts | **bullets** |

Prose is only the connective "why" between visuals. Prefer **mermaid over ASCII
art** — it renders; an agent parses ASCII as a code block. Every diagram gets a
one-line legend.

## Precise — bind claims to evidence

A claim that lives only in prose is one refactor from silent staleness. Push each
to the strongest rung the toolchain supports:

```
prose  →  comment  →  test  →  type / lint / CI rule
(weakest, drifts)              (strongest, can't drift)
```

- A doc that says "X is enforced / lives at Y / always Z" **names the test, path,
  or type** that makes it true. Tag load-bearing claims by rung
  (`[law]` / `[structural]` / `[prose]`) so staleness risk is visible at a glance.
- Give load-bearing claims **stable IDs** (numbered invariants) so they're citable.
- A **doc-drift guard** (paths/claims checked against reality in CI) is what keeps
  "precise" from rotting — add one when a repo's docs reference real files.

## Procedure — writing or fixing a doc

1. **Place it.** Which reader, which tier (why / what-next / where / how)? Wrong
   tier ⇒ duplication. A new hard-to-reverse decision ⇒ an ADR, not a paragraph.
2. **Lead with the claim**, then structure: `summary` → section map → body, general
   → specific.
3. **Reshape each block** into its visual form (table / list / mermaid / arrows);
   keep prose for the connective why only.
4. **Bind every load-bearing claim** to its real enforcer (path / test / type) —
   read the code to find it, don't guess; mark `[prose]` only when nothing enforces
   it yet (and note it's worth promoting).
5. **Cut narrative + duplication**; replace a cross-tier repeat with a link.

## Smell test — quick audit before shipping

- Longest unbroken paragraph **> ~150 words** (or a structureless line enumerating
  things) → break into a table/list.
- A doc that lists or compares things with **zero tables** → probably prose-walling.
- A flow or state machine described only in prose or ASCII → make it mermaid.
- An "always / never / is enforced" claim with nothing behind it → bind or downgrade.

## Anti-patterns

- **Narrative log** ("in session X we found…") instead of a reusable reference.
- **Duplicating across tiers** — copies drift; link instead.
- **A fat always-injected file** — every token there is paid every turn.
- **ASCII art** where mermaid renders; **a diagram with no legend**.
- **Unbound "is enforced"** claims; **fragmenting** a small doc for no reason.

## Worked exemplar (this machine)

`/srv/share/projects/pagu/docs/` is the reference implementation — study one doc
before writing a new doc-set:

- `AGENTS.md` — the index + lean tier-0 entrypoint (a one-line role per doc).
- `docs/WORKFLOW.md` — the doc-tier table + the enforcement ladder.
- `docs/invariants.md` — an at-a-glance table of rung-tagged claims.
- `docs/diagrams/` — mermaid with a "reading the diagram" legend.
- `docs/CONCEPTS.md` §"Deep modules with progressive disclosure".
