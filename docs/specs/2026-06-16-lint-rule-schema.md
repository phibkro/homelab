---
summary: Schema design for `nori.lint` — a Reader+Writer dispatcher that unifies
  the homelab's grep-shaped lint rules into a declarative TOML registry consumed
  by a Nix dispatcher. Replaces scripts/checks/forbidden-patterns.sh. Graduated
  to implementation 2026-06-16; this spec retained for the design-trail it
  records.
status: graduated to implementation (2026-06-16). Code at modules/lint/
  (default.nix dispatcher + rules.toml registry); reference doc in
  docs/invariants.md § "Custom flake checks". Spec preserved for the open-
  questions trail + the data-vs-control-plane reasoning that informed the
  TOML choice over the originally-proposed Nix attrset.
trigger: Phase 3c (bash extraction) committed 2026-06-16; operator surfaced the
  N-walks-per-N-rules waste and proposed a single-pass Reader/Writer dispatcher
  the same shape as nori.lanRoutes.
---

# Spec — `nori.lint` rule schema (Phase 3d)

> **Graduated to implementation 2026-06-16.** The spec stays as the
> design-trail record; live code is in `modules/lint/`. Two refinements vs
> this spec landed during execution:
>
> 1. **Location** — operator pushed back on `modules/infra/lint.nix`;
>    `effects/` is for Reader+Writer modules that affect SYSTEM state
>    (filesystem, network, hardening). Lint is dev-time tooling, so it
>    lives at `modules/lint/` as a new top-level category.
> 2. **Config format** — operator surfaced that rules are pure data,
>    not Nix code. Rules moved from the proposed `rules.nix` (Nix
>    attrset) to `rules.toml` (TOML data), parsed via `builtins.fromTOML`.
>    Clean data / control plane split; portable if dispatcher language
>    ever changes. See `modules/lint/default.nix` header for the
>    rationale.

## Goal

Unify the per-script lint rules at `scripts/checks/{forbidden-patterns,doc-coherence,routing-coherence}.sh` into **one declarative rule registry** dispatched by **one engine**. Each rule is a piece of data; the engine walks the tree once and applies all rules.

Same shape as `nori.lanRoutes` (one declarative input → many generators), `nori.backups` (single intent declared per service), `nori.harden` (per-service hardening as data). This applies the homelab's own effect-interface pattern to its own checking infrastructure.

## Why this is the right answer

```
Current (Phase 3c)                       Proposed (Phase 3d)
──────────────────                       ───────────────────
N walks of modules/ per script           One walk; rules visit each file once
~8 rules × ~140 lines bash               ~8 rules × ~5 lines attrset
Bash arrays as the only abstraction      Typed schema (mkOption + submodule)
Hard to filter ("security-only run")     Trivial — filter the attrset
Hard to swap grep → tree-sitter-nix      Stable Reader; swap the Writer engine
Rule's WHY far from its WHAT             Co-located in the descriptor
```

The architectural payoff is that the **rule shape becomes a typed contract** — `types.submodule { pattern = types.str; scope = types.listOf …; … }`. The lint system inherits the correctness-by-construction posture from the rest of the `nori.<X>` effects.

## Proposed schema

```nix
options.nori.lint = mkOption {
  type = types.attrsOf (types.submodule ({ name, ... }: {
    options = {
      scope = mkOption {
        type = types.listOf types.str;
        example = [ "modules/" "machines/" ];
        description = "Paths the engine grep-walks for this rule.";
      };
      pattern = mkOption {
        type = types.str;
        example = "\\$pbkdf2-";
        description = ''
          The regex/grep pattern. Engine chooses -E vs basic based on
          a `extended` toggle if added later.
        '';
      };
      excludeFiles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "modules/infra/networking/default.nix" ];
        description = "File paths exempted from the rule.";
      };
      excludePatterns = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "100\\.100\\.100\\.100" ];
        description = "Substrings/regexes filtered out of matches before failing.";
      };
      message = mkOption {
        type = types.str;
        description = "Operator-facing explanation when the rule fires.";
      };
      docLink = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = ".claude/skills/add-oidc-client/";
        description = "Optional pointer to the skill / runbook that explains the why.";
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "security" "naming" ];
        description = "For filtering subsets (`just lint --tag security`).";
      };
    };
  }));
  default = { };
};
```

Consumer side — one generator:

```nix
checks.${system}.lint = pkgs.runCommandLocal "lint" {
  nativeBuildInputs = [ pkgs.bash pkgs.gnugrep ];
} ''
  bash ${dispatchLintRules config.nori.lint}
  touch $out
'';
```

Where `dispatchLintRules` is a Nix function that lowers the attrset to one bash script doing a single-pass walk.

## Existing rules to translate

From `scripts/checks/forbidden-patterns.sh`:

| Rule name (slug) | Notes |
|---|---|
| `pbkdf2` | inline OIDC hashes |
| `clientSecretHash` | removed-field reference |
| `caddyVirtualHosts` | direct vhost bypass — exclude lan-route + caddy |
| `blockyCustomDNS` | direct DNS bypass — exclude lan-route |
| `caddyAcmeInternal` | acmeCA = "internal" gotcha |
| `gatusNtfyUrl` | embedded topic gotcha |
| `tailnetIp` | CGNAT IP outside registry — has pattern + file exclusions |
| `noriLan` | hard-coded `.nori.lan` URI |
| `migrationPhase` | P\d+ prep/cutover/landing tokens |

From `scripts/checks/doc-coherence.sh`:

| Rule name | Notes |
|---|---|
| `hostDeferred` | host in machines/ AND doc says "deferred" — needs per-host expansion. Different shape from the simple grep rules. |

From `scripts/checks/routing-coherence.sh`:

| Rule name | Notes |
|---|---|
| `claudeMdRouteExists` | Iterates extracted refs vs filesystem. Loop-shaped. |
| `referenceDocsRouted` | Iterates docs/reference/*.md vs CLAUDE.md. Loop-shaped. |
| `l1DocsRouted` | Iterates a hardcoded list of L1 docs. Loop-shaped. |

## Open design questions

1. **Composite rules.** Some rules iterate (`hostDeferred`, the routing-coherence loop rules) — they're not a single grep + filter. Either:
   - Add a `customCheck` field that's a shell snippet (escape hatch — re-introduces opaque bash per-rule).
   - Expand the schema to support a `forEach` field (`forEach = { source = "find machines -maxdepth 1 …"; rule = …; }`). Cleaner, more declarative.
   - Keep doc-coherence + routing-coherence as separate scripts and only unify the forbidden-patterns family in Phase 3d. Smaller surface, sooner ship.
2. **`excludePatterns` semantics.** `grep -vE` chain or final stream filter? The tailnet-IP rule has TWO exclusion patterns piped — the order doesn't matter for OR-shaped exclusions. Decide whether the engine ORs or ANDs `excludePatterns`.
3. **Per-rule grep flags.** Some rules use `-rn`, others `-rln`, others `-rEn`. Standardize to `-rEn` or expose a `flags` field? Probably standardize; the field is one more variable to drift.
4. **Dispatcher language.** Bash today (matches existing posture). Could be Python/Rust later. The Reader stays the same; the Writer changes. Decide whether to bake the assumption that there can be multiple dispatchers (e.g., `dispatchLintRules-grep` + `dispatchLintRules-treesitter` later) into the schema design now.
5. **Where do the rules live in the tree?** Options:
   - `modules/infra/lint.nix` — schema + dispatcher live together; rules are declared in flake.nix `checks` section.
   - `modules/lint/<rule-tag>.nix` — one file per rule category. More files but cleaner per-rule co-location.
   - `flake.nix` — rules + dispatcher all there. Most concentrated; loses the deep-modules property.

## Out of scope for Phase 3d

- **`every-service-has-{backup-intent,fs-hardening}`** stay separate. They use Nix list interpolation (`${mkCasePattern ...}`) for the exclusion list — a different shape from text-pattern rules. Could be expressed in the schema with a different rule kind, but adds complexity to the v1.
- **AST-based checks.** No rule today demands AST awareness; the grep dispatcher is fine. Schema should be agnostic so a future AST dispatcher swap doesn't break the Reader contract.
- **Custom message formatting / SARIF / GitHub Actions integration.** Operator runs locally; CI uses `nix flake check`. No need yet.

## Validation plan

For each existing rule, after translation:

1. Drop the old `scripts/checks/<file>.sh` invocation
2. Add the equivalent `nori.lint.<name>` attrset
3. Run the new dispatcher and the old script against the same tree
4. Assert identical violation list (or note the discovered behavior parity gap)
5. Only after all rules pass parity — delete `scripts/checks/forbidden-patterns.sh`

The other two scripts (doc-coherence, routing-coherence) decision-bound to question (1) above.

## References

- `docs/plans/2026-06-16-docs-deep-sweep.md` — parent plan; this spec is a follow-up sub-phase
- `scripts/checks/forbidden-patterns.sh` — the rules to translate
- `modules/infra/networking/default.nix` — canonical shape of a `nori.<X>` effect with mkOption + types.submodule + assertions; serves as the structural template
- `modules/infra/backup/default.nix` — second worked example
- `docs/invariants.md` — the catalog this lint system enforces against (every `[law: foo]` row maps to a flake check; this consolidates them)
