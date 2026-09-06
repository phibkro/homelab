# Documentation map

Start with [the shared agent guide](../AGENTS.md) for source ownership and effect boundaries.

The documentation has one lifecycle per kind of knowledge. Current behavior
belongs in reference or generated docs; future outcomes belong in the roadmap;
an accepted change contract belongs in a spec; hard-to-reverse rationale belongs
in an ADR; operational recovery belongs in a runbook.

## Start here

| Document | Use when |
|---|---|
| [glossary.md](glossary.md) | Establishing the repository vocabulary and concern boundaries |
| [invariants.md](invariants.md) | Changing a load-bearing claim or deciding how it should be enforced |
| [roadmap.md](roadmap.md) | Choosing the next outcome or recording explicitly deferred work |
| [reference/module-authoring.md](reference/module-authoring.md) | Adding or restructuring inventory, profiles, modules, or workloads |
| [reference/services.md](reference/services.md) | Adding a service, backup policy, hardening, or observability |
| [reference/deployment.md](reference/deployment.md) | Planning, building, reviewing, or activating a change |
| [reference/topology.md](reference/topology.md) | Placing a workload or reasoning about host roles and failure domains |
| [reference/network.md](reference/network.md) | Changing routes, DNS, Caddy, Tailscale, audiences, or authentication |
| [reference/storage.md](reference/storage.md) | Changing filesystems, datasets, snapshots, replication, or backups |
| [reference/agentic-workflow.md](reference/agentic-workflow.md) | Changing agent tooling, hooks, delegation, or safety policy |
| [reference/runtime-tests.md](reference/runtime-tests.md) | Adding an operator-triggered integration or runtime test |
| [reference/recovery.md](reference/recovery.md) | Diagnosing an outage or selecting a recovery runbook |
| [reference/testing-methodology.md](reference/testing-methodology.md) | Choosing evaluation, build and real runtime evidence |
| [reference/documentation-writing.md](reference/documentation-writing.md) | Updating source comments, generated docs or prose |
| [reference/capacity-baseline.md](reference/capacity-baseline.md) | Locating recorded capacity observations and their limits |

Generated documents in `generated/` are committed projections of
Nix declarations; edit their source comments or inventory, then regenerate.

The [process model](specs/2026-09-06-process-model.md) is a retained design
model informing the current organization: it names procedures, data flows,
retained state and separate realization and authority relations. The current
Nix and Ansible realizations implement these concerns directly; no modeling or
compiler layer is mandatory. The earlier [realization
experiment](specs/2026-09-06-domain-realization.md) is also a retained design
experiment; its bounded media checker is historical exploration, not a current
enforcement requirement.

The [complete reorganization spec](specs/2026-09-06-complete-reorganization.md)
records the accepted old-to-new path mapping and its cleanup contract. The
[two-host migration spec](specs/2026-09-06-two-host-migration.md) records the
current two-host organization. Use the [OneTouch cutover runbook](runbooks/onetouch-backup-cutover.md)
for the backup transition; its gates require live evidence before retirement.

## Document lifecycle

| Location | Owns | Does not own |
|---|---|---|
| [roadmap.md](roadmap.md) | Outcome-level backlog and named deferrals | Detailed implementation steps or completed-work history |
| `specs/` | Accepted problem, design, constraints, and verification contract | Live operational truth after the change lands |
| `decisions/` | Durable rationale for costly-to-reverse decisions | Routine implementation detail |
| `reference/` | Current architecture and authoring guidance | Aspirational future state |
| `runbooks/` | Executable incident, maintenance, and recovery procedures | Design rationale |
| `archive/plans/` | Retained multi-phase execution plans with historical value | Canonical current status |
| `archive/reports/` | Retrospectives, audits, evidence, and migration outcomes | Forward work |
| `archive/legacy-plans/` | Retained root-level plans | Current operational instructions |
| `installs/` | Machine and agent onboarding procedures | General module authoring |

This repository deliberately does not add `docs/work/active/`: the existing
roadmap plus one accepted spec per substantial outcome already provides the same
control surface. Adding a second active-work tree would duplicate status.

## Adding or updating documentation

1. Put the fact in the narrowest existing document whose lifecycle matches it.
2. Prefer a generated projection when the fact already exists in inventory or
   evaluated Nix configuration.
3. Add a new document only when it has a distinct trigger and owner.
4. Link it from this map when it is a primary entry point.
5. Run `just check` for generated-document freshness. After moving files,
   also run `just check-migration` for the separate path-coherence checks.

For prose conventions and generated-document mechanics, see
`reference/documentation-writing.md`.
