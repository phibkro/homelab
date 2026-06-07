---
summary: "Single catalog of load-bearing claims with current enforcement tier (law/structural/prose/judgment). Drift candidates are visible. ADR-0001 explains the why."
tags: [reference, invariants, enforcement]
---

# Invariants

Load-bearing claims, each tagged by **how strongly enforced today**. Stronger tiers self-defend; weaker tiers drift silently.

Drift register: `[prose: unchecked]` = promotion candidate.

Enforcement ladder (strongest → weakest):

```
[law]  →  [structural]  →  [runtime-introspection]  →  [prose: unchecked]
                                                          ↑
                                                  drift lives here
```

See ADR-0001 for *why* prose alone is the staleness floor.

## At a glance

Strongest rung each claim has reached. "Promote?" notes mark `[prose: unchecked]` claims with a tractable mechanization path.

| Claim | Tier |
|---|---|
| **Security & isolation** | |
| Every service module declares `nori.harden.<unit>` (or names an exclusion) | `[law: every-service-has-fs-hardening]` |
| Every service has backup intent (`nori.backups.<svc>.paths` or `.skip = <reason>`) | `[law: every-service-has-backup-intent]` + `[runtime-introspection: just test-backups]` (fresh snapshot per target ≤25h) |
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
| One `nori.lanRoutes` entry generates Caddy vhost + Blocky DNS + Gatus monitor consistently | `[structural]` (single schema → multiple generators in `modules/effects/lan-route.nix`) + `[runtime-introspection: just test-routes]` (Caddy + DNS + HTTPS all reachable per declared route) |
| `audience: operator` routes get no Authelia overlay; `family` gets OIDC; `public` is intentionally open | `[structural]` (typed `audience` enum, generators branch on it) |
| Service names function over brand (`status`, not `gatus`; `chat`, not `ollama`) unless brand IS identity | `[prose: unchecked]` — promote? brand-name grep against a known list |
| **systemd units** | |
| Every `Restart=on-failure` unit's `ExecStart` is smoke-tested before landing (prevents restart-loop bombs that break the next `switch-to-configuration` — incident 2026-06-03 in `.claude/skills/gotcha-*/`) | `[prose: unchecked]` — promote? flake check resolving each `ExecStart` to a real nix-store binary path |
| **Convention shapes** | |
| `nori.<X>` effects are one input → multiple generators (Reader + collected-Writer interface) | `[structural]` (the abstraction shape itself; documented in `CONCEPTS.md` § effect-interface deep-dive) |
| Adding `modules/effects/<X>.nix` ships with a `just test-<X>` runtime introspection recipe | `[prose: unchecked]` — promote? meta-check that every Reader+Writer-shaped effect file has a matching test recipe in `Justfile`. See `docs/RUNTIME_TESTS.md` § "Next potential test targets" |
| A service module owns *everything* about its service in one file (no fan-out) | `[prose: unchecked]` — promote? per-service file boundary check |
| Rule of three before extracting an abstraction | `[judgment]` |
| Iterate-to-stable, then codify | `[judgment]` |
| Code is the single source of truth; docs approximate | `[judgment]` |

## Tiers

| Tier | Mechanism | Self-defending? | Use when |
|---|---|---|---|
| `[law: <check>]` | `flake.nix` `checks.${system}` derivation; CI fails on divergence. Token must match real check (`nix flake show .#checks`) | yes — divergence = test fail | claim is fully expressible as code-vs-rule check |
| `[structural]` | Bad state unrepresentable by construction (typed `audience` enum, required host folder + registry entry both fail eval) | yes (until refactor breaks the construction) | dangerous state can be locked out at the type/API surface |
| `[runtime-introspection]` | `just test-<X>` recipe queries the live system's registry against the declared intent (`docs/RUNTIME_TESTS.md`) | yes when test is run — typically pre-push, post-deploy | the declaration ↔ runtime gap is silent and the registry is queryable |
| `[prose: unchecked]` | No mechanical check; lives in docs/comments. The staleness risk | no — drift is invisible | nothing else fits yet; flag for promotion |
| `[judgment]` | Irreducible human design choice; code is downstream | n/a — not tracking code | the thing is taste, not derivable from anything |

**Promotion lattice:** `prose → [runtime-introspection | structural | law]` per claim's nature. Runtime introspection is the cheapest promotion when (a) declaration is a registry and (b) runtime exposes it queryable (the homelab's most common shape — see `docs/RUNTIME_TESTS.md` § "Four levers").

## Promotion work-list

`[prose: unchecked]` claims in rough priority order for mechanization:

1. **`disko-uses-by-id`** — grep `modules/services/*.nix` + `machines/*/disko*.nix` for `/dev/nvme[0-9]` or `/dev/sda[0-9]?` (only `by-id/*` permitted). **High value**: NVMe enumeration is unstable (gotchas.md); a single mistake wipes the wrong disk. **Implementation**: a new derivation in `flake.nix` `checks` that runs `rg` over the matching files.
2. **`function-named-subdomains`** — grep `nori.lanRoutes.*` declarations for brand names against a known list (`gatus`, `ntfy`, `jellyfin`, `immich`, `ollama`, `open-webui`, `beszel`, …). **Medium value**: noise prevention, not safety.
3. **`workhorse-vs-appliance-placement`** — derived check: for each service module, assert it's placed on a host whose role tag matches the service's declared role. Currently `nori.hosts` carries role tags; could be cross-referenced. **Medium value**: prevents accidental Pi-bloat.
4. **`systemd-execstart-resolves`** — scan all `systemd.services.*.serviceConfig.ExecStart` (and the user-services variant) and assert the first token resolves to a path inside the build closure. Won't catch invalid CLI flags (incident 2026-06-03) but catches the more common typo + uninstalled-tool failures that cause restart loops. **High value** given the incident class: a single mistake at ExecStart cascades into mass-service-outage on next rebuild because `switch-to-configuration`'s stop-timeout path doesn't run the start phase. Implementation: a check derivation iterating `config.systemd.services` and `config.home-manager.users.*.systemd.user.services`.

Others (the `[judgment]` ones) stay where they are — they're not staleness risks.

## Citation pattern

When a doc elsewhere relies on an invariant, cite it as `(INVARIANTS § <claim-short-name>)`. When a code comment relies on one, write `# invariant: see INVARIANTS § <claim-short-name>`. The catalog is the single home; the citations point in.

## See also

- `ENFORCEMENT.md` — the enforcement ladder mechanics + how to add a new rule
- `CONCEPTS.md` § enforcement ladder — the conceptual model
- `docs/decisions/0001-agentic-homelab-practices.md` — why prose alone is the staleness floor
