# ADR-0001: Agentic homelab practices — why this repo is shaped for amnesiac teammates

- Status: Accepted
- Date: 2026-06-03

## Context

This homelab is built primarily by LLM agents working one session at a time, with a single human operator (Philip). The useful mental model is **not "solo dev with tools" but an amnesiac team**: every session is a fresh teammate who must be onboarded from zero, does excellent work, then leaves — taking all tacit context with it.

Three asymmetries vs. a human team decide which software-team practices are worth adopting:

1. **Extreme bus factor — everyone quits at end of session.** Documentation isn't insurance against lost knowledge; it's the *primary transmission medium*. The onboarding artifact (`CLAUDE.md` → `docs/`) is the highest-leverage thing in the repo.

2. **Context is the scarce resource, not time.** Ceremony costs an agent almost nothing to *write*, but every doc is paid for again at *read* time, in context budget, every session. The cost model inverts: heavy write-time enforcement is cheap, but read-navigability must be optimized ruthlessly.

3. **Agents confabulate; "done" is the dangerous claim.** An agent asserts completion confidently and sometimes wrongly. Practices that **bind claims to verifiable evidence** are worth disproportionately more than for humans.

Homelab-specific constraints amplify these:

- NixOS rebuilds are operator-activated (a build error fails at compile, but a runtime error happens after `switch`). "Tests pass" is far from "service comes up."
- The blast radius spans irreplaceable state (workstation backups, Immich photos, Vaultwarden secrets) — wrong actions can't be Ctrl-Z'd.
- Multiple hosts (workstation, Pi, Mac) have different roles; cross-host invariants are not visible from a single file.

## Decision

Adopt the software-team practices that either **externalize tacit knowledge** or **verify a claim**. Skip the practices whose value was coordinating persistent humans across time.

The filter: *a practice transfers iff it externalizes knowledge or verifies a claim.*

## Consequences

This filter explains and justifies the existing shape of the homelab. It also gives a sharp test for proposed future practices.

**Practices that transfer (kept and codified):**

- **Heavy docs as code-equivalent.** The topic-triggered reference docs under `docs/reference/` (topology, storage, network, services, module-authoring, documentation-writing, recovery, runtime-tests, capacity-baseline), the mandatory docs root (`docs/glossary.md`, `docs/invariants.md`, `docs/roadmap.md`), the per-decision ADRs under `docs/decisions/` (with `0000-rationales.md` as the meta-index for smaller decisions), and the per-gotcha skills (`.claude/skills/gotcha-*/`) — one home per topic, no overlap. They're the onboarding artifact, not insurance.
- **Conventional commits + structured messages.** Commits encode the *why* for future-you; the conventional-commit type makes intent grep-able. This ADR layer carries the heavier decisions commit messages can't fit.
- **Skills for procedures, prose for facts.** Procedures (`add-service`, `add-host`, `relocate-to-pi`, `on-structural-change`, `wrap-session`, `wrap-feature`) live as skills under `home/claude-code/skills/`; they load on demand when their trigger fires, paying context only when relevant. Prose facts stay in `CLAUDE.md` and `docs/`.
- **Flake checks as binding contracts.** `every-service-has-fs-hardening`, `every-service-has-backup-intent`, `forbidden-patterns` derivations bind doc claims to CI evidence. A claim with a check is self-defending; a claim without is staleness-prone — `docs/invariants.md` is the catalog of which is which.
- **`nori.<X>` effect modules.** Each effect is one input → multiple generators (Reader + collected Writer). Single source for cross-cutting declarations: `nori.lanRoutes.<name>` generates Caddy + DNS + Gatus + dashboard from one entry. This *externalizes* the cross-cutting knowledge a human would otherwise have to remember.

**Practices that do NOT transfer (deliberately skipped):**

- **Feature branches / GitFlow.** Solo-with-agents. Branches don't coordinate non-existent multiple humans. Commit directly to `main`.
- **Code review as gate.** A fresh agent reviewing a fresh agent's diff is theater — neither has lived context to spot subtle drift. Replaced by structural enforcement (flake checks, types) where possible; operator review where structural is infeasible.
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
- `home/claude-code/CLAUDE.md` — operator's global rules across all projects; many are downstream of this ADR's filter.
