---
summary: "Load-bearing claims catalog + the enforcement ladder that keeps each one true. Every claim is tagged by its current rung (law / structural / runtime-introspection / prose / judgment); prose claims are drift candidates. Per-rung mechanics, the decision tree for new rules, and the promotion work-list live here. ADR-0001 explains why prose alone is the staleness floor."
tags: [reference, invariants, enforcement]
---

# Invariants

This is the homelab's single home for **load-bearing claims** and **how each one is kept true**. Two parts:

- **The catalog** (below, § "At a glance") — every load-bearing claim, tagged by its current rung on the enforcement ladder. Drift candidates (`[prose: unchecked]`) are visible.
- **The ladder** — the mechanics of each rung, from strongest (typed / lint / CI rule, can't drift) to weakest (prose, drifts the moment it's written).

Rules written as prose drift the moment they're written. Conventions are encoded as enforcement layers, preference order **types > assertions > flake checks > runtime introspection > comments > prose**. See `docs/decisions/0001-agentic-homelab-practices.md` for *why* prose alone is the staleness floor.

## The ladder

```
prose  →  comment  →  runtime-introspection  →  test  →  type / lint / CI rule
(weakest, drifts silently)                                     (strongest, can't drift)
```

| Rung | Mechanism | When it fires | Self-defending? | Use when |
|---|---|---|---|---|
| `[law: <check>]` | `flake.nix checks.${system}` derivation; CI fails on divergence. Token must match a real check (`nix flake show .#checks`). | `just check` (fast); `just check-all` (full) | yes — can't merge violation | claim is fully expressible as code-vs-rule check |
| `[structural]` | Bad state unrepresentable by construction (typed `audience` enum, required host folder + registry entry both fail eval). | NixOS eval phase | yes (until refactor breaks the construction) | dangerous state can be locked out at the type/API surface |
| `[runtime-introspection]` | `just test-<X>` recipe queries live registries against the declared intent (see `docs/reference/runtime-tests.md`). | operator-triggered post-deploy | yes when run; silent if forgotten | declaration ↔ runtime gap is silent and the registry is queryable |
| Comment | `# invariant: …` next to load-bearing code. | reader-time only | no — passive prompt | the why matters at this exact code site |
| `[prose: unchecked]` | No mechanical check; lives in this catalog. | reader-time only | no — drifts invisibly | nothing else fits yet; promotion candidate |
| `[judgment]` | Irreducible human design choice; code is downstream. | n/a — not tracking code | n/a | taste, not derivable from anything |

**The bias: push every load-bearing claim toward the rightmost rung the toolchain can reach.** A claim that lives only in prose is one refactor from silent staleness; a claim bound to a flake check fails CI the moment code diverges. Runtime introspection is the cheapest promotion when (a) declaration is a registry and (b) runtime exposes it queryable.

## At a glance

Strongest rung each claim has reached. `[prose: unchecked]` entries are promotion candidates; the work-list further below ranks them.

| Claim | Tier |
|---|---|
| **Security & isolation** | |
| Every service module declares `nori.harden.<unit>` (or names an exclusion) | `[law: every-service-has-fs-hardening]` |
| Every service has backup intent (`nori.backups.<svc>.paths` or `.skip = <reason>`) | `[law: every-service-has-backup-intent]` + `[runtime-introspection: just test-backups]` (fresh snapshot per target ≤25h) |
| Default-deny firewall — only compiler-selected route/listener ports open on their declared interfaces | `[structural]` (`inventory/default.nix`, `infra/common/nixos/inventory.nix`, and the Pi firewall template) |
| Tailnet is the auth perimeter; Authelia only for per-user identity | `[structural]` (the `audience` enum forces the choice at the type level) |
| `disko*.nix` configs reference disks by `/dev/disk/by-id/*`, never `/dev/nvmeN` | `[law: lint.diskoUsesById]` (promoted 2026-06-16; nori.lint TOML registry) |
| Every production SOPS file has one explicit recipient-set rule; no production catch-all can widen a new file | `[structural]` (`.sops.yaml`) |
| Never bulk-rename keys in SOPS-encrypted YAML because key names are authenticated data | `[prose: unchecked]` — edit through `sops` and re-encrypt with the intended recipient policy |
| **Topology & roles** | |
| Pi runs only appliance-safe services; every workload placement matches a typed role declared by its manifest | `[structural]` (closed role enum + pure inventory assertion) + `[law: eval-workload-role-placement]` |
| Cross-host references consume the compiler's typed host and route projections; adapters do not reconstruct addresses or hostnames | `[structural]` (`inventory/default.nix` → `config.nori.inventory` and the generated Pi inventory) |
| Each managed host has one entry in `inventory/hosts.nix` with one explicit backend; NixOS entries name system/home modules and Ansible entries name plan/apply/verify commands; the inventory compiler rejects incomplete or inconsistent declarations | `[structural]` (`inventory/default.nix` + `lib/machines.nix`) |
| **Compiled workload routes** | |
| One manifest endpoint generates its backend route, firewall exposure, Pi Caddy/DNS data, monitor, and OIDC client metadata | `[structural]` (`services/*/manifest.nix` → `inventory/default.nix`) + `[runtime-introspection: just test-routes]` |
| Route declarations combine audience and reachability: operator routes cannot be internet-reachable; family routes must declare OIDC, forward-auth, or a documented no-auth reason; public Gatus routes cannot use the operator audience | `[structural]` (pure compiler assertions in `inventory/default.nix`) |
| Endpoint names describe function (`uptime`, not `gatus`; `chat`, not `open-webui`) unless the brand is the identity | `[law: lint.functionNamedSubdomains]` |
| **systemd units** | |
| Every `Restart=on-failure` unit's `ExecStart` is smoke-tested before landing | `[prose: unchecked]` — the 2026-06-03 bad-flag restart-loop incident is recorded in `docs/archive/plans/2026-06-21-improve-audit.md` finding 4 |
| **Convention shapes** | |
| `nori.<X>` effects are one input → multiple generators (Reader + collected-Writer interface) | `[structural]` (the abstraction shape itself; documented in `docs/glossary.md` § effect-interface deep-dive) |
| Adding a Reader+Writer concern under `infra/common/nixos/` ships with a `just test-<X>` runtime introspection recipe | `[prose: unchecked]` — promote? meta-check that every Reader+Writer-shaped effect file has a matching test recipe in `Justfile`. See `docs/reference/runtime-tests.md` § "Next potential test targets" |
| A workload manifest owns identity, activation, placement, endpoints, and listeners; its runtime adapter owns backend-specific realization | `[structural]` (compiler imports only the selected active runtime modules) |
| Rule of three before extracting an abstraction | `[judgment]` |
| Iterate-to-stable, then codify | `[judgment]` |
| Code is the single source of truth; docs approximate | `[judgment]` |

## Rungs in this repo

### Type system

Use option `type =` constraints first. Free, immediate, error message points at the option itself.

```nix
port     = mkOption { type = types.port; ... };       # 0..65535 enforced at eval
scheme   = mkOption { type = types.enum [ "http" "https" ]; ... };
audience = mkOption { type = types.enum [ "operator" "family" "public" ]; ... };
```

If the rule fits a type, write the type. Don't restate it in the description.

### Compiler and module assertions

Cross-attribute invariants fail during pure inventory compilation or NixOS
evaluation. Use them for placement, uniqueness, conditional requirements, and
other rules that no single option type can express.

```nix
assert lib.assertMsg (portCollisions == [ ])
  "inventory: resolved route/private listener port collision(s)";
```

Current route, placement, activation, role, and port-collision assertions live
in `inventory/default.nix`.

### Custom flake checks

Derivations under `checks.${system}.<n>` in `flake.nix`. Arbitrary shell, runs grep / find / scripts over the source tree. Use for repo-wide rules that don't live inside the module system.

For grep-shaped rules, the canonical home is `nori.lint` — a Reader (rule registry as data) + Writer (lowering dispatcher) split, with rules declared in `lint/rules.toml`:

```toml
[rules.<name>]
pattern = '<extended-regex>'        # literal string: backslashes verbatim
scope = ["infra/"]             # paths grep walks
excludeFiles = ["allowlist.nix"]    # optional per-rule file exemptions
excludePatterns = ['known-ok']      # optional per-rule substring exemptions
tags = ["security", "topology"]     # optional, for future filtering
docLink = "docs/reference/<name>.md#<section>" # optional durable pointer to the rationale
message = '''
Operator-facing explanation when the rule fires.'''
```

Dispatcher lives at `lint/default.nix`; wired in `flake.nix` via `lintLib.makeLintCheck { rules = builtins.fromTOML (builtins.readFile ./lint/rules.toml).rules; ... }`. Adding a rule = one TOML block.

Live examples in the `lint` check include `pbkdf2` (no inline OIDC hashes), `caddyVirtualHosts` (manifest-owned endpoint exposure), `tailnetIp` (no host `100.x.y.z` literals outside `inventory/hosts.nix`), `noriLan` (deprecated alias containment), `migrationPhase` (no decaying phase tokens), and `diskoUsesById` (NVMe safety). Standalone derivations cover non-grep rules such as `every-service-has-fs-hardening`, `every-service-has-backup-intent`, and `routing-coherence`.

`just check-migration` checks source-path coherence during restructures. The
migration-only consecutive-comment scanner was retired in the two-host cleanup:
it enforced a historical formatting preference rather than configuration
behavior. Nix formatting remains enforced by the pinned formatter in CI.

The `path-coherence` script is the comment-narrative counterpart to `routing-coherence`. It walks `.nix` files + selected docs and verifies repository-root `.nix` path references resolve to actual files. Path-string drift was a silent failure mode that bulk-sed migrations leave behind; the script turns it into a CI-style error during restructure phases. Three escape hatches: paths with `<placeholder>` syntax check against a glob (must match at least one file); lines annotated with `path-coherence: skip` are ignored; files containing `path-coherence: skip-file` (illustrative tutorials, skill prose) skip wholesale; block-scoped via `path-coherence: skip-block ... end-skip` for fenced markdown examples.

If a rule needs AST awareness, graduate to a tree-sitter-nix wrapper. Not currently present; introduce only when grep stops being enough. The data/control plane split (TOML rules + Nix dispatcher) makes the Writer-swap cheap when that day comes.

### Runtime introspection

`just test-<X>` recipes query live registries against declarations. Operator-triggered (typically pre-push, post-deploy). See `docs/reference/runtime-tests.md` § "Four levers" for the framework.

Live recipes:

- `just test-backups` — per-target snapshot ≤25h
- `just test-routes` — Caddy + DNS + HTTPS reachable per declared route
- `just test-observability` — scrape targets up, per-host series, heartbeat <90s
- `just test-hypr` — Hyprland binds match declared bindings

### CI gate

`.github/workflows/check.yml` runs the Nix checks and Pi static checks on pushes and pull requests. CI backs up the local gates; it does not execute operator-triggered live introspection or establish production health. See the workflow for exact jobs and commands.

## Decision tree — when to add a rule

When you write the words **"we should always..."** or **"don't ever..."** in prose, ask:

| Shape of the rule | Rung |
|---|---|
| Single option's value range / set | **type** (`types.port`, `types.enum`, `types.strMatching`) |
| Consistency across options (uniqueness, paths-XOR-skip, derived requirement) | **module assertion** |
| Forbidden text pattern in source files | **flake check (grep)** |
| Forbidden semantic pattern (needs eval introspection) | **flake check** via `nix eval` over `config.…` |
| AST-shape rule | **flake check** wrapping `tree-sitter-nix` (not yet present) |
| Declaration matches a queryable runtime registry (compiled routes → Caddy admin API; `nori.backups` → restic snapshots; Hyprland binds → `hyprctl binds -j`) | **runtime introspection** — new `just test-<X>` recipe per `docs/reference/runtime-tests.md` |
| None of the above | **judgment** — that's what review is for. Don't write it down; it'll rot |

### When NOT to add a rule

- The rule's **false positives outweigh real catches**.
- The **cost of the constraint exceeds the cost of fixing the violation**.
- Only one person in the project ever cares; let that person enforce it in review.

**A check earns its keep when it would have caught a real mistake, not a hypothetical one.** Add when violations occur or are imminent — not preemptively.

## Inventory enforcement — worked example

The manifest → compiler → adapter boundary uses all five rungs:

| Rung | Example |
|---|---|
| Type | Typed route and listener projections in `infra/common/nixos/inventory.nix` |
| Assertion | Explicit activation, placement validity, per-host port uniqueness, and route authentication in `inventory/default.nix` |
| Flake check | Inventory eval checks, backup/hardening intent checks, and the TOML lint registry |
| **Runtime introspection** | `just test-backups`, `just test-routes`, and `just test-observability` compare declarations with running services |
| CI gate | Declared Nix checks and Pi static checks run via `.github/workflows/check.yml`; live introspection remains operator-run |

## Promotion work-list

`[prose: unchecked]` claims in rough priority order for mechanization:

**Recently promoted:**
- `workhorse-vs-appliance-placement` → `[law: eval-workload-role-placement]` (2026-07-22) — workload manifests declare a non-empty set from the shared typed host-role vocabulary; the pure inventory compiler rejects every resolved placement whose host role is outside that set before NixOS module evaluation.
- `disko-uses-by-id` → `[law: lint.diskoUsesById]` (2026-06-16) — was register item #1; the rule that tested the "add a rule = one TOML block" Goal motivating the nori.lint refactor.
- `function-named-subdomains` → `[law: lint.functionNamedSubdomains]` (2026-06-16) — TOML denylist of 13 upstream brand names with clean function-name mappings (gatus→uptime, ntfy→alert, …). Audited current tree: zero real violations; the remaining brand identities are explicit exceptions such as `auth` for Authelia and `samba` for SMB.
- `audience-enforces-auth` → `[structural: compiler assertion]` (2026-06-21) — `audience="family"` requires `oidc`, `forwardAuth`, or explicit `noAuthReason` in `inventory/default.nix`. Legitimate native-auth exceptions remain explicit in their manifests.
- `infra-concerns-have-tests` → `[law: infra-concerns-have-tests]` (2026-06-21) — recursively discovers every shared `options.nori.*` schema and rejects any unaccounted file. Runtime-observable effects map to matching `test-*` recipes in `lib/flake-parts/checks/conventions.nix`. Hardware-bound GPU and Wi-Fi schemas and read-only host/inventory projections name their narrower evaluation/build evidence explicitly.
- `systemd-execstart-resolves` → REJECTED (2026-06-21) — vetted after audit proposed it; the source tree had no literal-path `ExecStart` values. Nix evaluation already validates every `${pkgs.foo}/bin/baz` interpolation. The 2026-06-03 failure came from valid binaries with bad flags, which a first-token check cannot catch. See `docs/archive/plans/2026-06-21-improve-audit.md` finding 4.

Others (the `[judgment]` ones) stay where they are — they're not staleness risks.

## Code style enforcement

`just check` runs the fast Nix checks, including statix, deadnix and formatting checks.
`just check-all` selects every declared check through that same metadata dispatcher,
including runtime VM suites. The pre-commit hook validates an isolated exact-index
snapshot with fast Nix and Pi static checks, fails on missing tools, and never fixes
the working tree. Run formatting or fixes explicitly. Hook and CI results cover their
tested content, not subsequent edits.

## Citation pattern

When a doc elsewhere relies on an invariant, cite it as `(invariants § <claim-short-name>)`. When a code comment relies on one, write `# invariant: see invariants § <claim-short-name>`. The catalog is the single home; the citations point in.

## See also

- `docs/decisions/0001-agentic-homelab-practices.md` — why prose alone is the staleness floor; the "amnesiac team" model that makes the rung ladder load-bearing
- `docs/reference/runtime-tests.md` — the runtime-introspection rung's framework (four levers)
- `docs/reference/documentation-writing.md` — the same enforcement bias applied to comments + prose
