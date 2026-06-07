# docs/

Reference for this homelab. Three read modes — the first is mandatory
at session start; the rest is reached on demand.

Filenames encode the topic; the `USE WHEN` column matches the
project's skill/memory trigger convention.

Same tables live in the root `CLAUDE.md`; this file mirrors them for
agents that land in `docs/` without that context.

## Read on session start (mandatory)

Without these, the agent doesn't know what it doesn't know — every
other doc reads as undefined jargon, and load-bearing claims get
silently broken.

| Doc | USE WHEN |
|---|---|
| `GLOSSARY.md`   | always, first — establishes vocabulary (`nori.<X>` family, audience, fate-sharing, value tiers). Every other doc references these |
| `INVARIANTS.md` | always, second — the drift register: load-bearing claims tagged by enforcement rung |

## Topic-triggered reference

Reach on demand when the USE-WHEN trigger fires. Filenames encode the
topic so `ls` is enough to find the right one.

| Doc | USE WHEN |
|---|---|
| `SKILL_INDEX.md`          | looking for a `/<skill-name>` that matches your intent — recurring procedures live as skills, not prose                              |
| `ROADMAP.md`              | considering deferring work, checking what's queued, or wondering whether something is already planned                                |
| `TOPOLOGY.md`             | placing a service across hosts, sizing caps, or reasoning about workhorse/appliance/agent roles                                      |
| `STORAGE.md`              | touching btrfs subvolumes, `nori.fs.<X>`, snapshot/backup policy, or value-tier classifications                                      |
| `NETWORK.md`              | adding a `nori.lanRoutes` entry, picking an audience, or working with Caddy + Authelia + DNS                                         |
| `SERVICES.md`             | adding a service module, picking a backup pattern (A/B/C), or wiring observability                                                   |
| `MODULE_AUTHORING.md`     | writing a new module — template, sops conventions, packages-by-scope, dev workflow                                                   |
| `DOCUMENTATION_WRITING.md`| writing/auditing comments + prose — earns-rent taxonomy, anti-patterns, the agent-imitation loop                                     |
| `ENFORCEMENT.md`          | promoting a claim from prose → comment → test → type, or picking the rung for a new rule                                             |
| `RECOVERY.md`             | something is broken or you're planning recovery — RTO targets, runbook index, permanent constraints                                  |
| `RUNTIME_TESTS.md`        | adding a `just test-<X>` lever or auditing whether an effect family ships with one                                                   |
| `RATIONALES.md`           | wondering "why was X chosen?" before re-litigating a design decision                                                                 |
| `PROJECTS.md`             | orchestrating work across the several projects on this machine (homelab, occupational-health, pagu, bang-lang, …)                    |
| `capacity-baseline.md`    | sizing a new service against current RAM/disk/CPU baselines per host                                                                 |

## Drill-down

Pulled in only when a parent doc cross-refs it. Not reached
opportunistically.

| Path | USE WHEN |
|---|---|
| `decisions/`               | per-ADR for each hard-to-revisit choice. `0001-agentic-homelab-practices.md` is the meta-ADR — read when philosophy comes up    |
| `runbooks/`                | per-incident recovery procedures (drive failure, USB enumeration, network split)                                                |
| `baremetal-install.md`     | bringing up a fresh NixOS host via nixos-anywhere                                                                               |
| `vm-install.md`            | bringing up a NixOS VM (testing, throwaway environments)                                                                        |
| `agent-onboarding-test.md` | validating a new agent's orientation against a small fixed task                                                                 |

## Adding a doc

1. Pick a read mode — mandatory, triggered, or drill-down. If you can't,
   the doc probably belongs in an existing one.
2. Topic-encoding filename (UPPER_SNAKE_CASE for top-level reference;
   lower-kebab-case for procedural how-tos under drill-down).
3. Write a USE-WHEN row for this `README.md` AND the matching table in
   root `CLAUDE.md`. If the trigger phrase is hard to write, the doc's
   purpose isn't sharp enough yet.
4. Lead by example per `DOCUMENTATION_WRITING.md`: tables + lists +
   visual shortcuts; prose only as connective tissue.
