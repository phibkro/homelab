---
summary: Glossary of the coined vocabulary (roles, `nori.<X>` effect family,
  value tiers, audience, split-module, fate-sharing, dev-shell fragments) AND
  the mental models that frame how the lab is reasoned about (amnesiac team,
  Reader+Writer effect interface, audience-driven trust topology, workhorse/
  appliance fate-sharing, enforcement ladder, value-tier protection tree).
---

# Concepts

The coined nouns/verbs this repo uses, plus the mental models that frame how
it's reasoned about. One line per term, pointing at the source-of-truth doc.
Read this to stop learning the vocabulary by osmosis; read the linked source
for the full shape.

A mental model is a *descriptive* internal representation of how something
behaves — a framework for reasoning / prediction, not a rule of action. Rules
and heuristics (rule of three, iterate-to-stable, declarative over imperative,
composable abstractions, tailnet-as-perimeter, workhorse-by-default) live in
CLAUDE.md § "What's the bias"; they're prescriptive. The models below are what
make those rules make sense.

## Glossary — coined nouns + verbs

| Term | Meaning | Source |
|---|---|---|
| **workhorse** | Host role: services land here by default — GPU, state-heavy, the HTTP entry plane. The `role` field on the host. | `modules/effects/hosts.nix` (`role`); set in `flake.nix` `identityFor` |
| **appliance** | Host role: only services that must survive the workhorse's failure (observability, alerting, DNS) or are network-appliance functions (subnet routing, exit node). Drives the placement assertion (appliance hosts can't use `paths`-based backups). | `modules/effects/hosts.nix`; assertion in `modules/effects/backup.nix` |
| **`nori.<X>`** | The repo's effect-interface family — one declarative input, many generated outputs. Reader + collected-Writer shape. | `modules/effects/`; see § "Effect interface deep-dive" below |
| **Reader (effect)** | `nori.<X>` flavor that hosts *produce* and services *read*: host-scoped context (`nori.hosts`, `nori.gpu`, `nori.fs`). Set in `flake.nix`/`hardware.nix`/`disko*.nix`. | `modules/effects/{hosts,gpu,fs}.nix` |
| **Writer (effect)** | `nori.<X>` flavor that services *contribute* and generators *interpret*: declarations assembled across modules (`nori.lanRoutes`, `nori.backups`, `nori.harden`). | `modules/effects/{lan-route,backup,harden}.nix` |
| **value tier** | Data-protection level driving snapshot/backup/retention: `re-derivable` (minimal) → `user`/`service` (daily + local) → `irreplaceable` (snapshots + local + off-site). | `modules/effects/fs.nix` (tier); STORAGE.md "Value tiers" |
| **audience** | Per-route trust level: `operator` (trusts tailnet, no Authelia) / `family` (needs OIDC for per-user state) / `public` (intentionally open). Decides where Authelia layers on. | `modules/effects/lan-route.nix` (`audience`); CLAUDE.md bias section |
| **split-module pattern** | Cross-host service shipped as two modules: daemon module on the host that runs it, client/proxy module on every host. Live: `beszel`, `ntfy`. | `modules/server/{beszel,ntfy}/`; `/relocate-to-pi` skill |
| **fate-sharing** | The placement test: a service moves to the appliance only when "fate-sharing breaks the function" (it must outlive the workhorse), not because it "feels lightweight." | TOPOLOGY.md "Service placement"; CLAUDE.md "workhorse-by-default" bias |
| **`mkDevShell` / fragment** | Atomic dev-environment fragment (`modules/dev/<n>.nix`: a toolchain/runtime/tool); the composer resolves transitive deps, dedupes inputs, merges Claude allowlists. `nix eval .#lib.fragmentNames` lists them. | `modules/dev/default.nix` (composer); `modules/dev/*.nix` (fragments) |

## Mental models — frameworks for reasoning about the lab

Each row is a *representation* — a picture of how some part of the system
behaves so you can predict, explain, or place new work without re-deriving from
first principles. These aren't rules; they're what makes the rules make sense.

| Model | What it represents | Source |
|---|---|---|
| **Amnesiac team** | Each agent session is a fresh teammate who quits at the end. Predicts which software-team practices transfer (anything that externalizes knowledge or verifies a claim — docs, tests, skills, INVARIANTS) and which don't (anything that assumes persistent humans — feature branches, code review as gate, onboarding meetings). | ADR-0001 |
| **Reader + collected-Writer effect interface** | Cross-cutting concerns assemble in two flavors: hosts *produce* read values (Reader: `nori.hosts`, `nori.gpu`, `nori.fs`), services *contribute* write values (Writer: `nori.lanRoutes`, `nori.backups`, `nori.harden`), generators *interpret* the collected whole. Predicts where any new abstraction lives. | `modules/effects/`; full prose below in § "Effect interface deep-dive" |
| **Audience-driven trust topology** | Trust isn't a property of a service — it's the intersection of *who's reaching it* (operator / family / public) and *what network layer they arrived on* (tailnet / LAN / internet). The auth stack is layered selectively from this intersection. Predicts where Authelia / OIDC layers on without re-litigating per service. | `modules/effects/lan-route.nix` (`audience`); CLAUDE.md "What's the bias" |
| **Workhorse / appliance fate-sharing** | A host's *role* defines what it must survive. A service migrates to the appliance only when "fate-sharing breaks the function" — its purpose requires outliving the workhorse. Predicts placement without taste arguments ("feels lightweight" isn't a reason). | TOPOLOGY.md "Service placement"; CLAUDE.md "workhorse-by-default" |
| **Enforcement ladder** | A claim's truth lives on `prose → comment → test → type / lint / CI rule`; each rung is a different mechanism for staying true. Predicts what protects a claim from drift, and which `[prose: unchecked]` items are worth promoting. | INVARIANTS.md; ENFORCEMENT.md |
| **Value-tier protection tree** | `re-derivable → user → service → irreplaceable` maps to a specific snapshot + local-backup + off-site-backup shape per tier. Predicts what to do with any new state-bearing service without designing protection per-service. | `modules/effects/fs.nix`; STORAGE.md "Value tiers" |

## Effect interface deep-dive

The `nori.<X>` family in `modules/effects/` is a structural Reader + collected-Writer effect interface. The NixOS module system handles both flavors via the same option-merge fixed-point semantics, which is why one folder holds them together; the distinction is in *who produces*:

| Shape | Examples | Producer | Consumer |
|---|---|---|---|
| Reader (host-scoped context) | `nori.hosts`, `nori.gpu`, `nori.fs` | hosts only — set in `flake.nix` `identityFor`, `hardware.nix`, `disko*.nix` | services |
| Collected Writer (assembled across modules, then interpreted) | `nori.lanRoutes`, `nori.backups`, `nori.harden` | services contribute | generators in `modules/effects/<x>.nix` and downstream handlers (`modules/server/backup/`, …) interpret |

Each `modules/effects/<x>.nix` is one effect's full surface:

- **type signature** — the `mkOption` schema with type constraints
- **contracts** — assertions (port uniqueness, DNS-safe names, host-aware appliance gating, …)
- **interpretation** — the `config = mkIf ... { ... }` block that turns the collected attrset into systemd services / Caddy vhosts / restic jobs / …

The convention is informal in the sense that nothing prevents a service from setting `nori.hosts` or a host from declaring `nori.lanRoutes` — those would be Reader/Writer violations. Today these are conventions, enforced via:

- **Type system** for shape constraints inside one option (port range, DNS-safe name regex)
- **Module assertions** for cross-attribute invariants (paths-XOR-skip, port uniqueness, appliance role can't use `paths`)
- **`forbidden-patterns` flake check** for textual violations (no `100.x.y.z` literals outside `flake.nix`'s `identityFor` — cross-host refs go through `config.nori.hosts.<name>.tailnetIp`)

**Adding an effect**: create `modules/effects/<n>.nix`, define the option schema + assertions + (if Writer-shaped) the consumer/handler logic. Import in `modules/common/default.nix`. Document the producer/consumer split in the file's header comment so future readers see the Reader/Writer shape at a glance.
