---
summary: "Single catalog of load-bearing claims with current enforcement tier (law/structural/prose/judgment). Drift candidates are visible. ADR-0001 explains the why."
tags: [reference, invariants, enforcement]
---

# Invariants

Load-bearing claims about this homelab, each tagged by **how strongly it is enforced today**. A `[law: …]` claim is bound to a CI check (rename the check or violate the claim → build fails); a `[prose: unchecked]` claim drifts silently unless someone notices.

This file is the **drift register**: anything tagged `[prose: unchecked]` is a promotion candidate. The bias is `prose → comment → test → type/lint/CI rule` (see ADR-0001 for the why).

## At a glance

Strongest rung each claim has reached. "Promote?" notes mark `[prose: unchecked]` claims with a tractable mechanization path.

| Claim | Tier |
|---|---|
| **Security & isolation** | |
| Every service module declares `nori.harden.<unit>` (or names an exclusion) | `[law: every-service-has-fs-hardening]` |
| Every service has backup intent (`nori.backups.<svc>.paths` or `.skip = <reason>`) | `[law: every-service-has-backup-intent]` |
| Default-deny firewall — only Caddy ports open by default | `[structural]` (modules/common firewall config) |
| Tailnet is the auth perimeter; Authelia only for per-user identity | `[structural]` (the `audience` enum forces the choice at the type level) |
| `disko*.nix` configs reference disks by `/dev/disk/by-id/*`, never `/dev/nvmeN` | `[prose: unchecked]` — promote? `forbidden-patterns` grep |
| Sops-encrypted secrets stay in `secrets/secrets.yaml`; encryption itself is structural | `[structural]` (sops policy file `.sops.yaml`) |
| Never bulk-rename keys in sops-encrypted yaml (AAD-bound ciphertext breaks) | `[prose: unchecked]` — can't really mechanize; lives in `gotchas.md` |
| **Topology & roles** | |
| Pi runs only services that survive workstation outage (observability / alerting / DNS / network plumbing) | `[prose: unchecked]` — promote? per-service role-vs-host cross-check |
| Cross-host service split: daemon on one host, client/proxy on every consumer; cross-host refs via `nori.hosts` registry | `[structural]` (the registry IS the wiring) |
| Each host has one folder at `machines/<n>/`; identity registered in `nori.hosts`; eval fails if folder + registry don't both land | `[law: add-host eval check]` (via `add-host` skill's exit invariant) |
| **lanRoutes** | |
| One `nori.lanRoutes` entry generates Caddy vhost + Blocky DNS + Gatus monitor consistently | `[structural]` (single schema → multiple generators in `modules/effects/lan-route.nix`) |
| `audience: operator` routes get no Authelia overlay; `family` gets OIDC; `public` is intentionally open | `[structural]` (typed `audience` enum, generators branch on it) |
| Service names function over brand (`status`, not `gatus`; `chat`, not `ollama`) unless brand IS identity | `[prose: unchecked]` — promote? brand-name grep against a known list |
| **Convention shapes** | |
| `nori.<X>` effects are one input → multiple generators (Reader + collected-Writer interface) | `[structural]` (the abstraction shape itself; documented in `CONCEPTS.md`) |
| A service module owns *everything* about its service in one file (no fan-out) | `[prose: unchecked]` — promote? per-service file boundary check |
| Rule of three before extracting an abstraction | `[judgment]` |
| Iterate-to-stable, then codify | `[judgment]` |
| Code is the single source of truth; docs approximate | `[judgment]` |

## Tiers

`[law: <check-name>]` — bound to an executable check in `flake.nix` `checks.${system}`. The strongest tier: CI fails if code diverges from the stated meaning. The claim is **self-defending** — it cannot silently go stale, because divergence is a test failure. The `<check-name>` token must be a substring of a real check (verify with `nix flake show .#checks`).

`[structural]` — enforced by construction, not by a runtime test: the dangerous state is unrepresentable. A typed `audience` enum forces the auth choice; a missing host folder + missing registry entry both cause flake eval to fail. Checked by `nix eval` or by the absence of an API, not by a property test. Strong, but verify the construction still holds when refactoring the thing that makes it true.

`[prose: unchecked]` — a real semantic claim with *no mechanical check* today. These are the staleness risks: nothing fails if the code drifts. Each is a candidate to **promote** to `[law]` or `[structural]`. The "Promote?" notes above identify the tractable ones.

`[judgment]` — a design choice not derivable or checkable from code (it is the thing code is downstream *of*). Not a staleness risk because it does not track code; it is what code tracks. Listed so an agent knows these are the irreducible human decisions — read these first; the rest is downstream.

## Promotion work-list

`[prose: unchecked]` claims in rough priority order for mechanization:

1. **`disko-uses-by-id`** — grep `modules/server/*.nix` + `machines/*/disko*.nix` for `/dev/nvme[0-9]` or `/dev/sda[0-9]?` (only `by-id/*` permitted). **High value**: NVMe enumeration is unstable (gotchas.md); a single mistake wipes the wrong disk. **Implementation**: a new derivation in `flake.nix` `checks` that runs `rg` over the matching files.
2. **`function-named-subdomains`** — grep `nori.lanRoutes.*` declarations for brand names against a known list (`gatus`, `ntfy`, `jellyfin`, `immich`, `ollama`, `open-webui`, `beszel`, …). **Medium value**: noise prevention, not safety.
3. **`workhorse-vs-appliance-placement`** — derived check: for each service module, assert it's placed on a host whose role tag matches the service's declared role. Currently `nori.hosts` carries role tags; could be cross-referenced. **Medium value**: prevents accidental Pi-bloat.

Others (the `[judgment]` ones) stay where they are — they're not staleness risks.

## Citation pattern

When a doc elsewhere relies on an invariant, cite it as `(INVARIANTS § <claim-short-name>)`. When a code comment relies on one, write `# invariant: see INVARIANTS § <claim-short-name>`. The catalog is the single home; the citations point in.
