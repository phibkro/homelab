# ADR-0001: Agentic homelab practices — why this repo is shaped for amnesiac teammates

- Status: Accepted
- Date: 2026-06-03

> Historical rationale. Current operational rules live in `AGENTS.md` and
> `docs/reference/agentic-workflow.md`. They supersede this ADR's branching,
> concurrency, review, and effect-authorization details.

## Context

This homelab is built primarily by LLM agents that can work concurrently but do not retain reliable tacit context between assignments. The useful mental model is **not "solo dev with tools" but a rotating team**: each agent must recover context from durable sources and leave verified artifacts for its successor.

Three asymmetries vs. a human team decide which software-team practices are worth adopting:

1. **Extreme bus factor — agents rotate.** Documentation is not insurance against lost knowledge; it is the primary transmission medium. The onboarding path (`AGENTS.md` → `docs/`) is the highest-leverage surface in the repository.

2. **Context is the scarce resource, not time.** Ceremony costs an agent almost nothing to *write*, but every doc is paid for again at *read* time, in context budget, every session. The cost model inverts: heavy write-time enforcement is cheap, but read-navigability must be optimized ruthlessly.

3. **Agents confabulate; "done" is the dangerous claim.** An agent asserts completion confidently and sometimes wrongly. Practices that **bind claims to verifiable evidence** are worth disproportionately more than for humans.

Homelab-specific constraints amplify these:

- NixOS rebuilds are operator-activated (a build error fails at compile, but a runtime error happens after `switch`). "Tests pass" is far from "service comes up."
- The blast radius spans multiple machines and irreplaceable state. Cross-host invariants are not visible from one file.

## Decision

Adopt the software-team practices that either **externalize tacit knowledge** or **verify a claim**. Skip the practices whose value was coordinating persistent humans across time.

The filter: *a practice transfers iff it externalizes knowledge or verifies a claim.*

## Consequences

This filter explains and justifies the existing shape of the homelab. It also gives a sharp test for proposed future practices.

**Practices that transfer (kept and codified):**

- **Heavy docs as code-equivalent.** Topic-triggered references under `docs/reference/`, the mandatory docs root (`docs/glossary.md`, `docs/invariants.md`, `docs/roadmap.md`), and per-decision ADRs under `docs/decisions/` each have one home with no overlap. Correctness-critical landmines live beside the source or in durable topic documents.
- **Conventional commits + structured messages.** Commits encode the *why* for future-you; the conventional-commit type makes intent grep-able. This ADR layer carries the heavier decisions commit messages cannot fit.
- **Skills for procedures, prose for facts.** Cross-provider procedures live in the shared agent-skill source. Project-specific procedures live under `.claude/skills/` until the neutral `.agents/` surface supports them. Prose facts stay in `AGENTS.md` and `docs/`. Memory can aid discovery but is not an authority.
- **Flake checks as binding contracts.** `every-service-has-fs-hardening`, `every-service-has-backup-intent`, and the lint derivations bind document claims to CI evidence. A claim with a check is self-defending; a claim without one is staleness-prone. `docs/invariants.md` catalogs the enforcement tier.
- **Pure inventory compiler.** Host and workload declarations are each written once. `inventory/default.nix` validates their complete graph and generates NixOS, Ansible, deployment, public, and documentation projections. This externalizes cross-cutting knowledge without a second registry.

**Practices that do NOT transfer (deliberately skipped):**

- **Long-lived process branches / GitFlow.** Branch ceremony does not replace artifact verification. Use the worktree and branching rules in `AGENTS.md` for current isolation requirements.
- **Review without evidence as a gate.** Independent review can find defects, but it does not prove correctness. Structural checks, runtime evidence, and operator review remain the acceptance gates.
- **Onboarding meetings / pairing.** No persistent humans to onboard. The docs *are* the meeting.
- **Backlog grooming as recurring meeting.** `docs/roadmap.md` is the single home, edited in place.

**Implications for new practices:**

When proposing a new homelab rule or convention, apply the filter explicitly:

- *Does it externalize tacit knowledge?* → likely keep.
- *Does it verify a claim?* → likely keep; reach for structural enforcement.
- *Does it only coordinate humans across time?* → skip; it doesn't apply here.

When a prose rule survives, ask "what's its enforcement tier?" (`docs/invariants.md`). Promote `prose → comment → test → type/lint/CI rule` wherever feasible. Pure prose is fragile in this setup.

## Alternatives considered

- **"Just trust the agent."** Rejected: the third asymmetry (confabulation) makes unverified claims structurally unreliable. Trust must be paired with mechanical verification.
- **"Document everything heavily, mechanize nothing."** Rejected: prose without enforcement decays. Pure documentation is the staleness floor, not the load-bearing tier.
- **"Mechanize everything, document nothing."** Rejected: not every load-bearing claim is mechanizable (judgment calls, design rationale, architectural why). Docs are necessary; the question is which rung of the enforcement ladder each claim sits on.

## Related

- `docs/invariants.md` — catalog of load-bearing claims with current enforcement tier (some are `[prose: unchecked]` — explicit promotion candidates).
- `docs/invariants.md` — the prose on the enforcement ladder; this ADR is the *why*.
- `users/nori/programs/agent-soul/SOUL.md` — provider-neutral global rules across all projects; many are downstream of this ADR's filter.
