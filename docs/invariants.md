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
| `[law: <check>]` | `flake.nix checks.${system}` derivation; CI fails on divergence. Token must match a real check (`nix flake show .#checks`). | `nix flake check` (CI + pre-commit) | yes — can't merge violation | claim is fully expressible as code-vs-rule check |
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
| Default-deny firewall — only Caddy ports open by default | `[structural]` (modules/common firewall config) |
| Tailnet is the auth perimeter; Authelia only for per-user identity | `[structural]` (the `audience` enum forces the choice at the type level) |
| `disko*.nix` configs reference disks by `/dev/disk/by-id/*`, never `/dev/nvmeN` | `[law: lint.diskoUsesById]` (promoted 2026-06-16; nori.lint TOML registry) |
| Sops-encrypted secrets stay in `secrets/secrets.yaml`; encryption itself is structural | `[structural]` (sops policy file `.sops.yaml`) |
| Never bulk-rename keys in sops-encrypted yaml (AAD-bound ciphertext breaks) | `[prose: unchecked]` — can't really mechanize; lives in gotcha skill |
| **Topology & roles** | |
| Pi runs only services that survive workstation outage (observability / alerting / DNS / network plumbing) | `[prose: unchecked]` — promote? per-service role-vs-host cross-check |
| Cross-host service split: daemon on one host, client/proxy on every consumer; cross-host refs via `nori.hosts` registry | `[structural]` (the registry IS the wiring) |
| Each host has one folder at `machines/<n>/`; identity registered in `nori.hosts`; eval fails if folder + registry don't both land | `[law: add-host eval check]` (via `add-host` skill's exit invariant) |
| **lanRoutes** | |
| One `nori.lanRoutes` entry generates Caddy vhost + Blocky DNS + Gatus monitor consistently | `[structural]` (single schema → multiple generators in `modules/effects/lan-route.nix`) + `[runtime-introspection: just test-routes]` (Caddy + DNS + HTTPS all reachable per declared route) |
| `audience: operator` routes get no Authelia overlay; `family` gets OIDC; `public` is intentionally open | `[structural]` (typed `audience` enum, generators branch on it) |
| Service names function over brand (`status`, not `gatus`; `chat`, not `ollama`) unless brand IS identity | `[law: lint.functionNamedSubdomains]` (promoted 2026-06-16; nori.lint TOML denylist of 13 upstream brands with clean function-name mappings) |
| **systemd units** | |
| Every `Restart=on-failure` unit's `ExecStart` is smoke-tested before landing (prevents restart-loop bombs that break the next `switch-to-configuration` — incident 2026-06-03 in `.claude/skills/gotcha-*/`) | `[prose: unchecked]` — promote? flake check resolving each `ExecStart` to a real nix-store binary path |
| **Convention shapes** | |
| `nori.<X>` effects are one input → multiple generators (Reader + collected-Writer interface) | `[structural]` (the abstraction shape itself; documented in `docs/glossary.md` § effect-interface deep-dive) |
| Adding `modules/effects/<X>.nix` ships with a `just test-<X>` runtime introspection recipe | `[prose: unchecked]` — promote? meta-check that every Reader+Writer-shaped effect file has a matching test recipe in `Justfile`. See `docs/reference/runtime-tests.md` § "Next potential test targets" |
| A service module owns *everything* about its service in one file (no fan-out) | `[prose: unchecked]` — promote? per-service file boundary check |
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

### Module assertions

Cross-attribute invariants checked at NixOS eval time. Eval fails atomically with the message you wrote.

```nix
assertions = [
  {
    assertion = lib.length ports == lib.length (lib.unique ports);
    message = "lanRoutes have duplicate backend ports.";
  }
];
```

Live examples in `modules/effects/lan-route.nix` (port uniqueness, name regex, redirectPath shape). Use when a rule depends on multiple options together — derived properties, uniqueness across attrs, conditional requirements.

### Custom flake checks

Derivations under `checks.${system}.<n>` in `flake.nix`. Arbitrary shell, runs grep / find / scripts over the source tree. Use for repo-wide rules that don't live inside the module system.

For grep-shaped rules, the canonical home is `nori.lint` — a Reader (rule registry as data) + Writer (lowering dispatcher) split, with rules declared in `modules/lint/rules.toml`:

```toml
[rules.<name>]
pattern = '<extended-regex>'        # literal string: backslashes verbatim
scope = ["modules/"]                # paths grep walks
excludeFiles = ["allowlist.nix"]    # optional per-rule file exemptions
excludePatterns = ['known-ok']      # optional per-rule substring exemptions
tags = ["security", "topology"]     # optional, for future filtering
docLink = ".claude/skills/<>/"      # optional pointer to the why
message = '''
Operator-facing explanation when the rule fires.'''
```

Dispatcher lives at `modules/lint/default.nix`; wired in `flake.nix` via `lintLib.makeLintCheck { rules = builtins.fromTOML (builtins.readFile ./modules/lint/rules.toml).rules; ... }`. Adding a rule = one TOML block.

Live examples in the `lint` check: `pbkdf2` (no inline OIDC hashes), `caddyVirtualHosts` + `blockyCustomDNS` (single-source via `nori.lanRoutes`), `caddyAcmeInternal` + `gatusNtfyUrl` (gotcha patterns), `tailnetIp` (no `100.x.y.z` literals outside `identityFor`), `noriLan` (legacy alias migration), `migrationPhase` (no decaying phase tokens), `diskoUsesById` (NVMe safety). Plus standalone derivations for non-grep rules: `every-service-has-fs-hardening`, `every-service-has-backup-intent`, `routing-coherence`, `doc-coherence`.

If a rule needs AST awareness, graduate to a tree-sitter-nix wrapper. Not currently present; introduce only when grep stops being enough. The data/control plane split (TOML rules + Nix dispatcher) makes the Writer-swap cheap when that day comes.

### Runtime introspection

`just test-<X>` recipes query live registries against declarations. Operator-triggered (typically pre-push, post-deploy). See `docs/reference/runtime-tests.md` § "Four levers" for the framework.

Live recipes:

- `just test-backups` — per-target snapshot ≤25h
- `just test-routes` — Caddy + DNS + HTTPS reachable per declared route
- `just test-observability` — scrape targets up, per-host series, heartbeat <90s
- `just test-hypr` — Hyprland binds match declared bindings
- `just test-replicas` — replication verifier oneshots

### CI gate

`.github/workflows/check.yml` runs `nix flake check` on every push and pull_request. Backstop for cases where pre-commit was skipped: commits from a Mac without nix on PATH (the most common case here), `git commit --no-verify`, agents that bypass the hook. The check itself is just `nix flake check --print-build-logs`; everything in the rungs above runs through it.

## Decision tree — when to add a rule

When you write the words **"we should always..."** or **"don't ever..."** in prose, ask:

| Shape of the rule | Rung |
|---|---|
| Single option's value range / set | **type** (`types.port`, `types.enum`, `types.strMatching`) |
| Consistency across options (uniqueness, paths-XOR-skip, derived requirement) | **module assertion** |
| Forbidden text pattern in source files | **flake check (grep)** |
| Forbidden semantic pattern (needs eval introspection) | **flake check** via `nix eval` over `config.…` |
| AST-shape rule | **flake check** wrapping `tree-sitter-nix` (not yet present) |
| Declaration matches a queryable runtime registry (`nori.backups` → restic snapshots; `nori.lanRoutes` → Caddy admin API; hyprland binds → `hyprctl binds -j`) | **runtime introspection** — new `just test-<X>` recipe per `docs/reference/runtime-tests.md` |
| None of the above | **judgment** — that's what review is for. Don't write it down; it'll rot |

### When NOT to add a rule

- The rule's **false positives outweigh real catches**.
- The **cost of the constraint exceeds the cost of fixing the violation**.
- Only one person in the project ever cares; let that person enforce it in review.

**A check earns its keep when it would have caught a real mistake, not a hypothetical one.** Add when violations occur or are imminent — not preemptively.

## Live `nori.<X>` enforcement — worked example

The effect-interface family in `modules/effects/` is enforced by all five rungs simultaneously:

| Rung | Example |
|---|---|
| Type | `port`, `audience`, `scheme`, name regex on `nori.lanRoutes.<n>` |
| Assertion | port uniqueness; paths-XOR-skip on `nori.backups`; appliance role can't use `paths`; DynamicUser `StateDirectory` symlink-trap check |
| Flake check | `every-service-has-fs-hardening`, `every-service-has-backup-intent`, `lint` (TOML rule registry; 10 rules covering security, topology, gotchas, migration drift, NVMe safety, doc hygiene) |
| **Runtime introspection** | `just test-backups` (per-target snapshot ≤25h), `just test-routes` (Caddy + DNS + HTTPS per route), `just test-observability` (scrape targets up, per-host series, heartbeat <90s) |
| CI gate | All of the above run on every push via `.github/workflows/check.yml` |

## Promotion work-list

`[prose: unchecked]` claims in rough priority order for mechanization:

1. **`workhorse-vs-appliance-placement`** — derived check: for each service module, assert it's placed on a host whose role tag matches the service's declared role. Currently `nori.hosts` carries role tags; could be cross-referenced. **Medium value**: prevents accidental Pi-bloat. **Implementation:** needs eval-time module assertion, not nori.lint (semantic, not grep-shaped).
2. **`systemd-execstart-resolves`** — scan all `systemd.services.*.serviceConfig.ExecStart` (and the user-services variant) and assert the first token resolves to a path inside the build closure. Won't catch invalid CLI flags (incident 2026-06-03) but catches the more common typo + uninstalled-tool failures that cause restart loops. **High value** given the incident class: a single mistake at ExecStart cascades into mass-service-outage on next rebuild because `switch-to-configuration`'s stop-timeout path doesn't run the start phase. **Implementation:** a check derivation iterating `config.systemd.services` and `config.home-manager.users.*.systemd.user.services` (eval-time, not nori.lint).

**Recently promoted:**
- `disko-uses-by-id` → `[law: lint.diskoUsesById]` (2026-06-16) — was register item #1; the rule that tested the "add a rule = one TOML block" Goal motivating the nori.lint refactor.
- `function-named-subdomains` → `[law: lint.functionNamedSubdomains]` (2026-06-16) — TOML denylist of 13 upstream brand names with clean function-name mappings (gatus→status, ntfy→alert, …). Audited current tree: zero real violations (operator's branded apps `filmder`/`heim`/`hermes` legitimately have brand-as-identity).

Others (the `[judgment]` ones) stay where they are — they're not staleness risks.

## Code style enforcement

`nix flake check` runs `statix` (anti-patterns) + `deadnix` (unused bindings) + `nixfmt` (format) automatically. Pre-commit hook in `.githooks/pre-commit` runs the same on staged `.nix` changes.

Bypass with `git commit --no-verify` for emergencies only — CI catches what pre-commit skipped.

## Citation pattern

When a doc elsewhere relies on an invariant, cite it as `(invariants § <claim-short-name>)`. When a code comment relies on one, write `# invariant: see invariants § <claim-short-name>`. The catalog is the single home; the citations point in.

## See also

- `docs/decisions/0001-agentic-homelab-practices.md` — why prose alone is the staleness floor; the "amnesiac team" model that makes the rung ladder load-bearing
- `docs/reference/runtime-tests.md` — the runtime-introspection rung's framework (four levers)
- `docs/reference/documentation-writing.md` — the same enforcement bias applied to comments + prose
