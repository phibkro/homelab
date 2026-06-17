---
summary: Research seed for two adjacent problems the operator surfaced
  end-of-session. (1) Generate `nori.<X>` option docs from existing
  `description` fields instead of paraphrasing them in prose (rustdoc/
  jsdoc/Zig pattern; OpenAPI-from-types analogy). (2) Audit + adopt
  Google's Open Knowledge Format v0.1 (published 2026-06-12, 4 days
  before this seed) — we already use markdown + frontmatter, so OKF
  compliance is likely a quick win.
status: research seed — no execution yet
trigger: 2026-06-16 end-of-session, operator surfaced both as "take
  note" while picking Sprint 4 (function-named-subdomains promotion).
  Two distinct but adjacent problems; one spec because they share the
  same surface (`docs/`) + the same end-state aspiration (less hand-
  maintained prose, more generation from code).
---

# Spec — Generated docs + Open Knowledge Format audit

> **Research seed.** Two threads worth investigating together because
> they share both the surface (`docs/`) and the underlying axiom
> (derive over duplicate, per SOUL.md "Single source of truth"). No
> execution yet — this is design framing for a future sprint.

## Problem 1 — Generate docs from existing option `description` fields

### Observation

The `nori.<X>` effect family already carries rich `description` fields
on every `mkOption` declaration. Today those descriptions are read
only at:

- Eval time (when an operator queries `nix repl` or hits an error)
- Editor tooling, if any (the Nix LSP exposes them)
- Anyone manually reading `modules/infra/<X>.nix`

Meanwhile, `docs/reference/*.md` paraphrases the same information in
prose, which:

- Drifts the moment the option schema changes (the inventory caught
  multiple instances in Sprint 1)
- Pays write cost at edit time AND read cost on every session

This is the **derive-don't-duplicate** anti-pattern the deep-sweep
explicitly named (per `docs/reference/documentation-writing.md` §
"Lists derived from code — derive from code, never duplicate in prose").
We've been ignoring it for option docs because no tool was wired up.

### Solution space — prior art

| Ecosystem | Tool | Shape |
|---|---|---|
| Rust | `rustdoc` | `///` doc comments extract → HTML/markdown |
| JavaScript | `JSDoc` / `TypeDoc` | `/** ... */` extract → HTML/markdown |
| Zig | builtin doc generator | `///` extract → HTML |
| OpenAPI | various | typed schema + structured comments → OpenAPI spec → SDK + docs |
| NixOS | `nixosOptionsDoc` (in nixpkgs lib) | option declarations → CommonMark |

`nixosOptionsDoc` is the native answer:

```nix
let
  optionsDoc = pkgs.nixosOptionsDoc {
    inherit (eval) options;
  };
in
optionsDoc.optionsCommonMark  # → markdown file we can publish
```

It already exists in nixpkgs lib. Our `nori.<X>` modules already use
the right description field shape. Drop-in derivable for near-zero
implementation cost.

### Goal (when this becomes a sprint)

Generate per-`nori.<X>` option-reference markdown into `docs/auto/`
(gated by a `docs-fresh` flake check). Cross-link from the existing
hand-written `docs/reference/*.md` doctrine docs ("for the option
schema details, see `docs/auto/lan-route.md`").

The hand-maintained reference docs stay — they carry the WHY,
patterns, examples, and cross-cutting prose that option descriptions
shouldn't carry. The schema details migrate to the generated layer.

### Open questions

1. **Where does generated content live?** `docs/auto/`? `docs/reference/`
   alongside the hand-maintained ones? Decide whether generated docs
   are visually distinct from hand-maintained (a `_generated.md` suffix?).
2. **CI gate?** A `docs-fresh` check that re-runs the generator + diffs
   against the committed version. Fails CI if checked-in copy drifted.
   Same shape as the proposed `routing-coherence` mechanism applied to
   doc generation.
3. **Eval entry point?** `nixosOptionsDoc` needs an evaluated config
   to traverse. Use the workstation host eval, or a synthetic config
   that imports just the effects without enabling any service?
4. **Cross-link mechanism?** Generated docs reference hand-maintained
   docs for the why; hand-maintained docs reference generated docs for
   the schema. How do we avoid stale links when an effect file moves?
   (Probably: the existing `routing-coherence` check generalizes.)

### Out of scope

- Generating docs from `description` fields on service modules
  (e.g. `modules/services/*.nix`). Service modules don't carry rich
  enough option descriptions today; the value/cost is worse than
  for `modules/infra/`.
- Replacing all hand-maintained reference docs with generated ones.
  The hand-maintained docs carry doctrine the schema can't.

## Problem 2 — Google Open Knowledge Format (OKF) v0.1 compliance

### Observation

Google Cloud published OKF v0.1 on **2026-06-12** (four days before
this seed). It's a vendor-neutral standard for representing the
metadata, context, and curated knowledge that AI agents need:

- Directory of markdown files
- YAML frontmatter
- Only mandatory field: `type`
- "No proprietary account or SDK to read, write, or serve"
- Renders on GitHub, ships as a tarball, mounts on any FS
- Full spec fits on a single page

This is **the exact shape our `docs/` tree already has** — markdown
files with frontmatter in a directory hierarchy. We didn't design
for OKF; we converged on the same pattern independently.

### Why this matters

OKF is the emerging interchange format for AI-agent knowledge bundles.
If our `docs/` tree complies (or can comply at low cost):

- Future agents (whether Claude Code, OpenCode, or whatever comes
  next) can consume the knowledge with no per-tool adaptation
- A bundle could be exported / shared / mounted into other agent
  workflows without translation
- Adjacent benefits: standardized frontmatter unlocks tooling
  (semantic search, indexers, embeddings pipelines) that the broader
  ecosystem is starting to ship

### Goal (when this becomes a sprint)

1. Read OKF v0.1 spec end-to-end
2. Audit our existing `docs/` tree against it
3. Decide which gaps are worth closing
4. Land the minimum compliance step that makes our docs OKF-readable

### Open questions

1. **`type` field on our frontmatter.** OKF requires a `type` field.
   Our current frontmatter has `summary:`, `tags:`, `status:`, etc.,
   but no `type:`. What `type` values would map onto our tier convention
   (mandatory L1 / topic-triggered L2 / drill-down L3)?
2. **Reserved filenames?** OKF specifies "a small number of reserved
   filenames." Do any of ours collide?
3. **Cross-linking conventions?** OKF specifies cross-linking rules.
   Do our `[[memory-name]]` and `docs/reference/<name>.md` references
   fit the spec, or need adapting?
4. **Semantic search opportunity?** OKF's standard frontmatter unlocks
   embedding-based search across the doc tree. Worth pursuing if (a)
   compliance is cheap and (b) we have a use case (a fresh agent
   semantic-searching the docs to find the right reference faster
   than the routing tables do).
5. **Where does OKF sit relative to our routing-coherence flake check?**
   Both are "is the doc tree well-formed?" mechanisms. Stack them or
   replace?

### Out of scope

- Adopting OKF-adjacent tooling (semantic search, indexers) — that's
  separate from compliance.
- Migrating docs/ wholesale to a different shape. The audit goal is
  "what changes if any?"; the actual migration is its own decision.

## Why these two problems share a spec

Both surface the same axiom: **derive over duplicate.** Generated docs
derive doc content from code. OKF compliance derives navigability /
semantic structure from frontmatter standards.

Both attack the **doc-maintenance cost** that the agentic-velocity
problem in the meta-Prologue surfaces. With agents producing
documentation at the same elevated rate as code, the cost of
hand-maintaining cross-references and schema descriptions becomes
the bottleneck.

The shared sprint structure (when these graduate):

```
1. Audit current docs/ tree
   - Against nixosOptionsDoc-derivable surface
   - Against OKF v0.1 compliance criteria

2. Decide minimum compliance moves
3. Land in order of cost-to-payoff ratio
4. Update CLAUDE.md routing tables + invariants
```

## When this becomes a plan

After at least one of:
- Operator surfaces an actual drift incident the generated docs would
  have caught (forcing function for problem 1)
- OKF spec finalizes (v1.0) or sees significant adoption (forcing
  function for problem 2)
- A semantic-search use case actually surfaces

Or just: the operator picks it as the next sprint after the current
Sprint 4 wrap.

## References

### Problem 1 — generated docs
- `nixosOptionsDoc` — in nixpkgs lib; `optionsCommonMark` attribute
- `docs/reference/documentation-writing.md` § "Lists derived from
  code" — names the anti-pattern this solves
- `docs/invariants.md` § "When to add a rule" — same SoT axiom
- Earlier roadmap item "Batch C: generated docs from live config" —
  spiritually adjacent; was about service/host placement tables,
  this spec extends to option schemas

### Problem 2 — OKF v0.1
- Spec: https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing/ (Google Cloud announcement, 2026-06-12)
- Coverage:
  - MarkTechPost — "Vendor-Neutral Markdown Spec for Giving AI Agents Curated Context"
  - heise — "Open Knowledge Format: AI Knowledge as Markdown Files"
- Search Engine Journal — full announcement

### Cross-spec
- ADR-0001 (agentic homelab practices) — the amnesiac-team axiom
  this both serves
- `docs/reference/agentic-workflow.md` § "Documentation as
  transmission medium" — why docs are load-bearing in this model
