# docs/

Reference for this homelab. Filenames encode the topic; the
`USE WHEN` column matches the project's skill/memory trigger
convention. Reach a doc on demand — only 1-3 are read-on-orient.

Same table lives in the root `CLAUDE.md`; this file is the mirror for
agents that land in `docs/` without that context.

## Map

| Doc                              | USE WHEN                                                                                                                            |
|----------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|
| `GLOSSARY.md`                    | first session here, OR you hit jargon (`nori.<X>` family, audience, fate-sharing, value tiers) and need the canonical definition    |
| `INVARIANTS.md`                  | a claim sounds load-bearing and you want its enforcement rung, OR before writing prose that asserts "X is always Y"                 |
| `SKILL_INDEX.md`                 | looking for a `/<skill-name>` that matches your intent — recurring procedures live as skills, not prose                             |
| `ROADMAP.md`                     | considering deferring work, checking what's queued, or wondering whether something is already planned                               |
| `TOPOLOGY.md`                    | placing a service across hosts, sizing caps, or reasoning about workhorse/appliance/agent roles                                     |
| `STORAGE.md`                     | touching btrfs subvolumes, `nori.fs.<X>`, snapshot/backup policy, or value-tier classifications                                     |
| `NETWORK.md`                     | adding a `nori.lanRoutes` entry, picking an audience, or working with Caddy + Authelia + DNS                                        |
| `SERVICES.md`                    | adding a service module, picking a backup pattern (A/B/C), or wiring observability                                                  |
| `MODULE_AUTHORING.md`            | writing a new module — template, sops conventions, packages-by-scope, dev workflow                                                  |
| `DOCUMENTATION_WRITING.md`       | writing/auditing comments + prose — earns-rent taxonomy, anti-patterns, the agent-imitation loop                                    |
| `ENFORCEMENT.md`                 | promoting a claim from prose → comment → test → type, or picking the rung for a new rule                                            |
| `RECOVERY.md`                    | something is broken or you're planning recovery — RTO targets, runbook index, permanent constraints                                 |
| `RUNTIME_TESTS.md`               | adding a `just test-<X>` lever or auditing whether an effect family ships with one                                                  |
| `RATIONALES.md`                  | wondering "why was X chosen?" before re-litigating a design decision                                                                |
| `PROJECTS.md`                    | orchestrating work across the several projects on this machine (homelab, occupational-health, pagu, bang-lang, …)                   |
| `decisions/`                     | per-ADR for each hard-to-revisit choice. `0001-agentic-homelab-practices.md` is the meta-ADR                                        |
| `runbooks/`                      | per-incident recovery procedures (drive failure, USB enumeration, network split)                                                    |
| `agent-onboarding-test.md`       | when bringing up a new agent — small fixed task to validate orientation                                                             |
| `baremetal-install.md`           | bringing up a fresh NixOS host via nixos-anywhere                                                                                   |
| `vm-install.md`                  | bringing up a NixOS VM (testing, throwaway environments)                                                                            |
| `capacity-baseline.md`           | current RAM/disk/CPU baselines per host                                                                                             |

## Conventions

- **Tier-1 (`GLOSSARY`, `INVARIANTS`, `SKILL_INDEX`)**: read-on-orient.
  Indexes + glossaries + the drift register.
- **Tier-2 (the rest of the top-level `.md` files)**: reference. Reach
  on demand when the USE-WHEN trigger fires.
- **Tier-3 (`decisions/`, `runbooks/`)**: drill-down. Pulled in only when
  the parent tier-2 doc cross-references them.

## Adding a doc

1. Pick a topic-encoding filename (UPPER_SNAKE_CASE for consistency).
2. Write a USE-WHEN row for both this `README.md` and the
   `Docs map` table in root `CLAUDE.md`. If you can't write a sharp
   USE-WHEN, the doc probably belongs in an existing one.
3. Lead by example per `DOCUMENTATION_WRITING.md`: tables + lists + visual
   shortcuts; prose only as connective tissue.
