# Documentation map

The documentation has one lifecycle per kind of knowledge. Current behavior
belongs in reference or generated docs; future outcomes belong in the roadmap;
an accepted change contract belongs in a spec; hard-to-reverse rationale belongs
in an ADR; operational recovery belongs in a runbook.

## Start here

| Document | Use when |
|---|---|
| `glossary.md` | Establishing the repository vocabulary and concern boundaries |
| `invariants.md` | Changing a load-bearing claim or deciding how it should be enforced |
| `roadmap.md` | Choosing the next outcome or recording explicitly deferred work |
| `reference/module-authoring.md` | Adding or restructuring inventory, profiles, modules, or workloads |
| `reference/services.md` | Adding a service, backup policy, hardening, or observability |
| `reference/deployment.md` | Planning, building, reviewing, or activating a change |
| `reference/topology.md` | Placing a workload or reasoning about host roles and failure domains |
| `reference/network.md` | Changing routes, DNS, Caddy, Tailscale, audiences, or authentication |
| `reference/storage.md` | Changing filesystems, datasets, snapshots, replication, or backups |
| `reference/agentic-workflow.md` | Changing agent tooling, hooks, delegation, or safety policy |
| `reference/runtime-tests.md` | Adding an operator-triggered integration or runtime test |
| `reference/recovery.md` | Diagnosing an outage or selecting a recovery runbook |

The remaining topic references are discoverable by their lowercase filenames in
`reference/`. Generated documents in `generated/` are committed projections of
Nix declarations; edit their source comments or inventory, then regenerate.

## Document lifecycle

| Location | Owns | Does not own |
|---|---|---|
| `roadmap.md` | Outcome-level backlog and named deferrals | Detailed implementation steps or completed-work history |
| `specs/` | Accepted problem, design, constraints, and verification contract | Live operational truth after the change lands |
| `decisions/` | Durable rationale for costly-to-reverse decisions | Routine implementation detail |
| `reference/` | Current architecture and authoring guidance | Aspirational future state |
| `runbooks/` | Executable incident, maintenance, and recovery procedures | Design rationale |
| `plans/` | Retained multi-phase execution plans with historical value | Canonical current status |
| `reports/` | Retrospectives, audits, evidence, and migration outcomes | Forward work |
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
5. Run `nix flake check`; generated-doc freshness and path-coherence checks are
   part of the gate.

For prose conventions and generated-document mechanics, see
`reference/documentation-writing.md`.
