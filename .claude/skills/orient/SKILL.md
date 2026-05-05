---
description: Homelab-specific supplement to the user-level /orient skill. Adds NixOS-flake-specific reading order (flake.nix → modules/effects → modules/server sample → hosts → Justfile → docs → CLAUDE.md last), and points at the lab's actual leverage map in CLAUDE.md § Leverage map. The framework + 12 leverage points + three-dimension structure live in the user-level skill at ~/.claude/skills/orient/SKILL.md.
when_to_use: Same as user-level /orient — fresh-context session, structural understanding wanted. The user-level skill carries the framework; this one adds the lab-specific reading order and points at the per-project tier placements.
---

# Orient — homelab-specific supplement

The framework — Meadows' 12 leverage points across three dimensions (artifact + dev workflow + agentic workflow), procedure, generic examples, caveats — lives in the **user-level** `~/.claude/skills/orient/SKILL.md`. Read that first.

This file adds two things specific to this homelab:

## Reading order for this codebase

NixOS flake; the canonical entry-point + abstraction-family reading order is:

1. `flake.nix` — entry point, `identityFor` host registry, `checks.${system}` rules suite
2. `modules/effects/*.nix` — the `nori.<X>` Reader+Writer effect family (`hosts`, `gpu`, `fs`, `lan-route`, `backup`, `harden`)
3. `modules/common/default.nix` — what every host imports
4. Sample 5-7 of `modules/server/*.nix` — representative service shapes (don't read all ~25)
5. `hosts/<host>/default.nix` per host — workstation + pi today
6. `Justfile` — operator workflows
7. `docs/{DESIGN,CONVENTIONS,gotchas}.md` — for *why*; trust code over doc when they conflict
8. `git log --oneline -20` — recent narrative
9. `CLAUDE.md` **last**, including its `## Leverage map` section for this lab's tier placements

## Where the per-project tier placements live

`CLAUDE.md § Leverage map` documents current placements at each tier across all three dimensions (artifact / dev workflow / agentic workflow). Read that section as the worked example *after* applying the user-level skill's framework to your fresh read — confirm the placements are still accurate, note where they've drifted, synthesize from there.

Drift is expected. Tier placements are dated; structural changes shift them. Treat the map as input, not gospel — your fresh read should agree on most placements, refine some, add what's missing.
