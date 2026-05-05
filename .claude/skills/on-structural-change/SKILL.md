---
description: Decide which doc tier (or skill, or memory) needs updating after a structural change just landed in the homelab — a new abstraction, pattern, convention, flake check, host, or cross-cutting decision that fresh agents would need to know about. Drift compounds, so this runs immediately after the change, not at session end.
when_to_use: A structural change just landed (or is about to) — phrases like "we just landed <abstraction>", "after this commit, anything else?", "what doc tier needs updating?", "I just merged X, what's the followup?". Also auto-invoke after committing a new file in `modules/lib/`, a new flake check, a new convention-codifying assertion, or a new host folder.
---

# On every structural change — refresh the doc tier

A "structural change" introduces a new pattern, abstraction, module shape, constraint, or convention that a fresh agent's mental model needs and that isn't obvious from one file's syntax.

Examples in this project: the `nori.<...>` family of attrset-keyed declarative options in `modules/lib/`, the topology registry, the cross-host service split pattern, the appliance/workhorse role split, each new flake check.

## The question to ask

**What would a fresh agent need to know that they couldn't derive from the code alone?**

If the answer is "nothing — it's self-documenting via flake check + module headers + assertions", you're done. If the answer is anything else, route the update to the right tier.

## Routing table

| Symptom | Action |
|---|---|
| Active example in `CLAUDE.md` or `docs/DESIGN.md` is now stale | Fix immediately. Drift acted on by the next agent is the highest-cost class. |
| New pattern used twice or more, with non-deterministic decisions per use | Codify as a skill in `.claude/skills/<n>/`. The cross-host service split → `relocate-to-pi` is the precedent. |
| New convention agents should follow (rule, not example) | Add to `docs/CONVENTIONS.md`, ideally backed by a flake check or module assertion. Rules in prose drift; rules in code don't. |
| Hard-won mistake worth surfacing (subtle gotcha, footgun) | Add to `docs/gotchas.md`. Each gotcha is an inoculation. |
| Cross-session fact (preferences, project state, host topology) | Update auto-memory in `~/.claude/projects/.../memory/`. Don't duplicate what's in CLAUDE.md. |
| Stale enumeration / count that mirrors code cardinality | Replace with a category description + live oracle (`nix flake show .#checks`, `just ports`, `ls modules/lib/`). Per `feedback/stratify_by_leverage` memory. |

## Specific patterns this session has seen

- **New `nori.<X>` lib module** → mention in CLAUDE.md "Composable abstractions" bias bullet (the family list); update CONVENTIONS.md "Service module template" if the abstraction changes how services declare their own config
- **New flake check** → no doc enumeration needed if you describe the category instead; if the check enforces a new convention, mention the convention in CONVENTIONS.md
- **New host** → CLAUDE.md "Topology + service placement" + `flake.nix` `identityFor` (eval enforces the latter); maybe `add-host` skill if the path is new
- **New cross-host split** → if it's the third instance, extract `mkCrossHostService` (rule of three); update `relocate-to-pi` skill
- **Stale doc artifact noticed** → fix it now, not at session end. The cost of an immediate update is small; the cost of a fresh agent acting on stale information is large.

## What NOT to do

- **Don't batch for session end.** Drift compounds. The cost asymmetry favors immediate updates.
- **Don't update docs that derive from code** — a list mirroring `modules/lib/` contents is drift-prone; describe the pattern + point at `ls modules/lib/`. (See `feedback/stratify_by_leverage` memory.)
- **Don't add to CLAUDE.md when a skill is the right home** — skills load on demand; CLAUDE.md is always-loaded context cost.
- **Don't write a procedure prose section when the procedure is non-deterministic and reusable** — extract to a skill instead.
- **Don't codify a pattern that's only been used once.** Wait for the third concrete use. Two instances look like a pattern but are often coincidence; the third reveals the actual axis of variation.

## Verification

After updating:

```bash
nix flake check       # new conventions backed by code shouldn't break anything
git diff --stat       # confirms only doc-tier files changed (vs accidental code edits)
```

The doc-touching `no-stale-paths` flake check catches cross-rename drift. There's an open Outstanding item to add a content-drift detector — until that lands, this skill is the manual replacement.
