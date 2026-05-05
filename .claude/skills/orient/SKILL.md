---
description: Build a structural understanding of this homelab codebase using Meadows' 12 leverage points. Two lenses (concrete software system + development workflow), grounded in concrete code reading. For fresh-context sessions where the agent needs a leverage-tiered map sharp enough to critique and evolve, not just describe — produces synthesis the user can act on, not a wall of file enumerations.
when_to_use: User starts a new session and wants comprehensive structural understanding. Phrases like "explore the codebase", "orient yourself", "get up to speed", "read in", "what's here". Invoke at session start before substantive work; skip for narrow procedural tasks ("fix bug X").
---

# Orient — leverage-tiered codebase exploration

Code is source of truth; docs are approximation. The goal is a structural map sharp enough to critique and evolve, not just describe.

## Two lenses

Map the lab through both:

1. **Concrete software system** — what runs, what's configured, what's enforced
2. **Development workflow as a system** — how the codebase evolves, what feedback loops exist, what the bias is

Each has its own observations at the same 12 leverage tiers. The dev-workflow lens is the easier one to miss; explicitly look for it.

## Meadows' 12 leverage points (low → high)

```
12  parameters, numbers (least leverage)
11  buffer sizes and stabilizing stocks
10  stock-and-flow structures
 9  lengths of delays
 8  negative feedback loops (regulation)
 7  positive feedback loops (gain)
 6  information flows (who has access)
 5  rules (constraints, incentives)
 4  power to self-organize / evolve structure
 3  goals of the system
 2  paradigm / mindset
 1  power to transcend paradigms (most leverage)
```

Each step up the tier is genuinely higher-impact. A fix at L12 (change a number) doesn't move what a fix at L5 (change a rule) moves.

## Procedure

### 1. Read code first, framework second

Don't open with labeling — that produces performative abstraction. Read actual files:

- `flake.nix` — entry point, host enumeration, `checks.${system}` rules
- `modules/effects/*.nix` — the `nori.<X>` abstraction family
- `modules/common/default.nix` — universal infra
- Sample 5-7 of `modules/server/*.nix` for shape (not every file)
- `hosts/<host>/default.nix` per host (workstation + pi today)
- `Justfile` — operator workflows
- `docs/{DESIGN,CONVENTIONS,gotchas}.md` for *why*; trust code over doc when they conflict
- `git log --oneline -20` for recent narrative
- `CLAUDE.md` **last** — it's a synthesis the codebase already produced; reading first biases your fresh read

Aim for ~30% of context budget here. The rest is for synthesis + the work the user actually wants done.

### 2. Place observations at leverage tiers

Tag what you read at appropriate Meadows tiers, per lens. **Don't copy the examples below verbatim** — verify each placement against the current code. Tiers shift as the codebase evolves; this list is from the session that defined the skill (2026-05-05) and may be stale.

**Concrete software system, current placements:**
- **L12** — port allocations (`just ports`), retention values, `MemoryMax` caps
- **L11** — `zramSwap = 16G`, OneTouch capacity, ML resource caps
- **L10** — `nori.fs` tier-driven flows; @streaming hardlink topology forcing same-subvol downloads + libraries
- **L9** — restic cadence ladder (daily / weekly / monthly / quarterly drill)
- **L8** — `OnFailure → notify@`, restic check, Gatus probes feeding ntfy
- **L7** — accumulating flake checks (each new check tightens future commits)
- **L6** — `nori.<X>` Reader+Writer effect family, topology registry, live oracles (`just ports`)
- **L5** — `every-service-has-fs-hardening` / `-backup-intent`, `forbidden-patterns`, `no-stale-paths`, `audience` enum
- **L4** — `modules/effects/` as the meta-shape; rule-of-three for abstraction extraction; skills system
- **L3** — DESIGN.md three principles: declarative reproducibility, default-deny, policy proportional to value
- **L2** — declarative-first, code-as-truth, FP-flavored Reader + collected-Writer effects, Cynefin Complex domain framing
- **L1** — willingness to swap tools when they fight the paradigm (Uptime Kuma → Gatus, forwardAuth → audience-aware tailnet trust)

**Development workflow, current placements:**
- **L8** — pre-commit hook + GitHub Actions CI as the corrective loop
- **L7** — `every-service-has-<X>` checks accumulate strictness; new conventions get codified
- **L6** — CLAUDE.md routing table + skills as on-demand context; `docs/PROCEDURES.md` index
- **L5** — "Encode conventions in code, not docs" (`feedback/enforce_in_code.md`); types > assertions > flake checks > prose
- **L4** — skills get extracted at three concrete uses; novel patterns iterate-to-stable then codify
- **L3** — "correctness > simplicity > thoroughness > speed"; "answer first, push back, no flattery" (operator preferences)
- **L2** — iterate-to-stable, then codify (Cynefin Complex); compose via aliases not categories
- **L1** — explicit willingness to question + restructure (the `audience` refactor was a paradigm move; "tailnet IS the auth" was another)

### 3. Synthesize — don't enumerate

End orientation with three things, not a wall of detail:

1. **3-5 highest-leverage active patterns** (what's already working at L4–L7) — the things you'd preserve
2. **1-3 leverage gaps** (places where a higher-tier intervention could replace lower-tier clutter) — the actionable improvements
3. **Paradigm + goals you inferred** (L1–L3) — name them explicitly so the user can confirm or correct your read

Don't list every service or every flake check — those are L12 details. Synthesize at the tier the user can act on.

The critique surface emerges automatically from leverage gaps: "this issue is at L12 (parameter); the meta-fix would be L5 (rule)" makes the leverage tiering visible and the impact quantifiable.

## Caveats

- **Meadows' 12 are descriptive, not prescriptive.** Some tiers may be empty for a subsystem; that's information ("no L1 paradigm-shift moves visible" tells you something).
- **Don't shoehorn** — if an observation doesn't sit cleanly at a tier, leave it ungrouped rather than mis-categorize.
- **For nascent codebases**, leverage tiers cluster at the higher end (paradigm + goals matter; rules haven't crystallized). For mature ones (this homelab), all 12 tiers usually have at least one observation.
- **For procedural tasks** ("fix this bug", "add this dependency"), this skill is overkill. Invoke at session start when the user wants orientation, not for micro-tasks.
- **Reading order matters.** The "code first, CLAUDE.md last" rule is load-bearing — CLAUDE.md is a synthesis the codebase already produced, and reading it first will bias your fresh read toward the existing synthesis rather than producing your own.

## Why this exists

Open-ended exploration prompts ("understand the codebase") produce thorough but unstructured reads — bottom-up file-by-file, leverage emerges only at synthesis time. A leverage-tiered framing produces top-down structural reads instead, faster orientation, sharper critique. The framework matches the codebase's own bias toward systems thinking (Cynefin's Complex, iterate-to-stable, encode-rules-in-code).

Pair with concrete grounding (read first, then map). Don't apply the framework abstractly without specific files in hand.
