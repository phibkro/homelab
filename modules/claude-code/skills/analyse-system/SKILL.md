---
description: Analyse a system using Meadows' 12 leverage points to produce a structural map sharp enough to critique and evolve, not just describe. Pick dimensions that separate the system's concerns; place observations at leverage tiers per dimension; synthesize 3-5 high-leverage active patterns + 1-3 leverage gaps + the inferred paradigm. Code is source of truth; docs are approximation. Pair with concrete reading — don't apply the framework abstractly without specific files in hand.
when_to_use: Fresh-context session that needs comprehensive structural understanding before substantive work — phrases like "explore the codebase", "analyse the system", "orient yourself", "get up to speed", "what's here". Skip for narrow procedural tasks ("fix bug X", "add this dependency") — the framework's leverage isn't worth the context budget for micro-work.
---

# Analyse a system via Meadows leverage points

Code is source of truth; docs are approximation. The goal is a structural map sharp enough to critique and evolve, not just describe.

## Choosing dimensions

A dimension is a lens that separates concerns within the leverage analysis. Picking the right ones is itself an analytical move — different systems benefit from different cuts. The dimensions you choose determine which observations cluster, which leverage gaps surface, and what synthesis becomes possible.

Useful starting point for typical software systems — three productive dimensions:

1. **Software artifact** — what's built; the code, config, and binaries that ship
2. **Development workflow** — how the artifact evolves; humans + automation iterating on it
3. **Agentic workflow** — how the agent (Claude, Copilot, etc.) participates in development; what context, tools, memory, skills it has

Other dimensions that work better for different systems:

- **Data plane / control plane / management plane** — distributed services
- **Domain / application / infrastructure** — DDD-flavored codebases
- **API surface / internals / ecosystem** — libraries with users
- **Production / staging / development** — env-axis for ops-heavy systems
- **Synchronous / batch / streaming** — timing-axis for data systems
- **Single instance / cluster / federation** — scale-axis for distributed systems

Pick the cut that best separates concerns for THIS system. The default three-dimension cut works for most software contexts; try it first, swap if the analysis feels forced.

## Meadows' 12 leverage points (low → high)

```
12  parameters, numbers (least leverage)
11  buffer sizes and stabilizing stocks
10  stock-and-flow structures
 9  lengths of delays
 8  negative feedback loops (regulation)
 7  positive feedback loops (gain, growth)
 6  information flows (who has access)
 5  rules (constraints, incentives)
 4  power to self-organize / evolve structure
 3  goals of the system
 2  paradigm / mindset
 1  power to transcend paradigms (most leverage)
```

Each step up the tier is genuinely higher-impact. A fix at L12 (change a number) doesn't move what a fix at L5 (change a rule) moves; an L1 move (transcend a paradigm) reshapes the problem space the lower tiers exist within.

Cross-dimension placements compound leverage. A single intervention that hits multiple dimensions at high tiers (e.g., a rule that changes both the artifact's structure AND the agent's behavior) is genuinely high-impact. Track the overlaps.

## Generic per-tier examples (artifact / dev / agentic dimension)

Use as grounding. Verify against the actual system being analysed — these are starting templates, not placements to copy.

| Tier | Software artifact | Development workflow | Agentic workflow |
|---|---|---|---|
| 12 | magic numbers, retry counts, hardcoded URLs, default timeouts | test timeouts, sleep durations, deploy intervals | token budgets, temperature, max-iterations |
| 11 | cache size, pool size, queue depth, batch size | CI runner count, test parallelism | context window size, memory file size |
| 10 | data flow architecture, ETL stages, message bus topology | branch model, release pipeline structure | system prompt → memory → prompt → tool → response flow |
| 9 | polling intervals, timeouts, batch cadence, retry backoff | CI cadence (per commit / PR / nightly), review cadence, deploy frequency | memory R/W cadence, cleanup/pruning cadence, context recall frequency |
| 8 | circuit breakers, rate limits, autoscalers, OOM-killer, timeout cascades | test failures gating commits, alert-on-error, rollback-on-regression | tool errors, validation feedback, user pushback, refusal logic |
| 7 | cache growth, log accumulation, queue depth growth, dependency creep | code growth, test suite size, dependency tree, doc volume | memory growth, skill accumulation, context drift, capability gain |
| 6 | logging, tracing, observability, type signatures vs implicit globals, pure functions vs side effects | code review visibility, ADRs, runbooks, who-knows-what | skill discovery, memory retrieval, what flows into the prompt |
| 5 | lint, types, tests, asserts, schemas, contracts | code review requirements, conventions, naming policies, ADR process | tool restrictions, hooks, settings.json policies, refusal rules |
| 4 | module boundaries, abstractions, APIs, plugin systems, DSLs | extraction patterns (functions/scripts/skills), refactor cadence | skill extraction, memory schema evolution, prompt restructuring |
| 3 | functional + non-functional requirements | quality bars ("correctness > speed"), process goals | agent goals (alignment, helpfulness, accuracy) |
| 2 | OOP / FP / event-driven / actor / dataflow / declarative | trunk-based vs feature-branch, IaC vs imperative ops | tool-use vs RAG vs in-context-learning vs ReAct |
| 1 | questioning architectural assumptions | questioning the dev process itself | questioning whether the agent should be involved at all |

## Procedure

### 1. Read code first, framework second

Don't open with labeling — that produces performative abstraction (the agent labels things "L6: information flows" without meaningfully understanding what flows where). Read actual files first.

For a typical project:

- Entry point — `main.*`, `index.*`, `flake.nix`, `Cargo.toml`, `package.json`, etc. Whatever defines the project's surface
- Core abstractions — `lib/` or `core/` or domain-model directories. Where the structural decisions live
- Module boundaries — `modules/`, `packages/`, `src/<components>/`. Sample 5-7 representative ones, don't read everything
- Workflow definitions — `Justfile`, `Makefile`, `.github/workflows/`, scripts directories
- Documentation — for *why*, but trust code over doc when they conflict
- Recent commit history — `git log --oneline -20` for narrative
- Project-level orientation files — CLAUDE.md, README.md, AGENTS.md, etc. — **last**, since they're syntheses the project already produced

Aim for ~30% of context budget here. Synthesis + actual work needs the rest.

### 2. Choose dimensions, place observations at leverage tiers

Decide your dimensions first (default three-cut, or something better-fit). As you read, tag what you observe at the appropriate Meadows tier within the appropriate dimension.

Don't shoehorn — if an observation doesn't sit cleanly, leave it ungrouped rather than mis-categorize. Empty tiers are information ("no L1 paradigm-shift moves visible in the dev workflow" tells you something about how the project evolves).

### 3. Synthesize — don't enumerate

End with three things, not a wall of detail:

1. **3-5 highest-leverage active patterns** (what's working at L4–L7, across dimensions) — the things you'd preserve
2. **1-3 leverage gaps** (places where higher-tier interventions could replace lower-tier clutter) — the actionable improvements
3. **Paradigm + goals you inferred** (L1–L3) — name them explicitly so the user can confirm or correct your read

Don't list every file or every rule — those are L12 details. Synthesize at the tier the user can act on.

The critique surface emerges automatically from leverage gaps: "this issue is at L12 (parameter); the meta-fix would be L5 (rule)" makes the leverage gap visible and the impact quantifiable.

## Caveats

- **Meadows' 12 are descriptive, not prescriptive.** Some tiers may be empty for a subsystem; that's information.
- **Don't shoehorn** — if an observation doesn't sit cleanly at a tier, leave it ungrouped rather than mis-categorize.
- **Dimensions are a tool, not a taxonomy.** Pick what separates concerns for THIS system. The artifact/dev/agentic cut is a default, not a requirement.
- **For nascent systems**, leverage tiers cluster at the higher end (paradigm + goals matter; rules haven't crystallized). Lower tiers may not have settled — accept the asymmetry.
- **For mature systems**, all 12 tiers usually have at least one observation per dimension.
- **For procedural tasks** ("fix bug X", "add this dependency"), this skill is overkill. Invoke at session start when the user wants orientation, not for micro-tasks.
- **Reading order matters.** "Code first, project orientation files last" is load-bearing — orientation files (CLAUDE.md, AGENTS.md, etc.) are syntheses the project already produced, and reading them first will bias the read toward the existing synthesis rather than producing your own.

## Project-specific extension

Projects can supplement this skill in two ways:

1. **A `Leverage map` section in their CLAUDE.md / AGENTS.md** documenting actual tier placements per dimension. Recommended path — keeps the per-project map alongside the rest of the project's orientation context, doesn't duplicate the generic framework.
2. **A project-level `.claude/skills/analyse-system/SKILL.md`** that supplements with project-specific guidance (e.g., "for this monorepo, also check the workspace config; for this Nix flake, also check `flake.nix` checks"). Optional; only when project-specific guidance is genuinely required.

## Why this exists

Open-ended exploration prompts ("understand the codebase") produce thorough but unstructured reads — bottom-up file-by-file, leverage emerges only at synthesis time. A leverage-tiered framing produces top-down structural reads instead, faster orientation, sharper critique. Pair with concrete grounding (read first, then map). Don't apply the framework abstractly without specific files in hand.
