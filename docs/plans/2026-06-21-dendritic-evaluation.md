---
summary: "Focused evaluation of the dendritic pattern (and the narrower flake-parts decomposition) for this homelab's flake.nix. Maps what concretely moves, identifies a three-tier decision (status-quo vs flake-parts vs full dendritic), names concrete costs + risks for each tier, and recommends a phased path."
status: PARTIALLY IMPLEMENTED — phases 1a + 2 + 3a landed; 3b + 4 remain
audited_commit: 125a07f
related: docs/plans/2026-06-21-improve-audit.md § finding #9 + § Direction D-C
---

> **Implementation status (2026-06-21)**:
> - ✓ Phase 1a — foundation (cfa59d5)
> - ✓ Phase 2  — formatter, devshell, machines, home (c247ef3, 7565241, etc.)
> - ✓ Phase 3a — 3 of 6 packages extracted (docs-backups, docs-fs,
>   docs-replicas) + shared helpers in lib/nixdoc.nix
> - ☐ Phase 3b — docs-{lan-route, topology, capabilities} still inline
>   (each has special multi-section structure; can't reuse the simple
>   helper. Mechanical extraction following the existing pattern.)
> - ☐ Phase 4  — 14 checks still inline (statix, deadnix, format, lint,
>   routing-coherence, every-service-has-{backup,hardening},
>   infra-concerns-have-tests, e2e-{pi,multi,restic,disk}-*, eval-*,
>   docs-fresh). Bulk of remaining work.
> - ☐ Phase 5  — verify byte-equality after 3b + 4 land.
>
> flake.nix went 1289 → 1126 lines (-163) after the partial extraction.
> Pattern is proven; the remainder is mechanical. Use the landed
> flake-parts/{formatter,devshell,machines,home,packages/docs-*}.nix
> as templates for the next files.

# Dendritic / flake-parts evaluation

## TL;DR

```
Status quo            flake-parts only        Full dendritic
(today)               (middle path)           (mightyiam pattern)
─────────             ────────────────        ─────────────────
1 file, 1055 lines    ~22 files, ~50 each     ~22+ files, auto-imported
explicit, opaque      explicit, modular       implicit, "drop a file"
no new dep            flake-parts             flake-parts + haumea (or import-tree)
0 day refactor        ~1-2 day refactor       ~2-3 day refactor
─────────             ────────────────        ─────────────────
nothing changes       flake.nix → ~40 lines   flake.nix → ~20 lines
                      all outputs are modular all outputs auto-imported
                                              auto-imported = "drop a file in
                                              modules/X/ and it lands"
```

**Recommendation**: go straight to **flake-parts only** (middle path). Skip full dendritic.

The two reasons full dendritic doesn't fit this repo:
1. The "no literal paths" + auto-import philosophy hides where outputs come from. Your existing CLAUDE.md routes operators + agents via explicit paths (`modules/services/<X>.nix`, `docs/reference/<topic>.md`); auto-import inverts that.
2. Your `modules/` NixOS tree is already well-organized + read by both NixOS module system AND tooling (lint walks `modules/services/*.nix` by glob). Auto-import via haumea adds a second indexer; risk of subtle interaction with your existing scanners (`routing-coherence`, `every-service-has-*`).

The middle path (flake-parts with explicit imports) gets you 80% of the value (flake.nix decomposed, each check/package its own file) without the auto-import philosophy clash.

## Concrete mapping for THIS flake.nix

What's in flake.nix today (line counts approximate):

```
INPUTS                                ~150 lines  → stays in flake.nix
machinesModule wrapper                   1 line   → flake-parts/machines.nix
homeModule wrapper                       1 line   → flake-parts/home.nix
devShells.${system}.default             10 lines  → flake-parts/devshell.nix (perSystem)
packages.${system}                     414 lines  → flake-parts/packages/{
  mkNixdocSection + mkFileDocstring     ~32 lines    → lib/nixdoc.nix (shared)
  docs-lan-route                        ~85 lines    → flake-parts/packages/docs-lan-route.nix
  docs-topology                        ~135 lines    → flake-parts/packages/docs-topology.nix
  docs-capabilities                     ~75 lines    → flake-parts/packages/docs-capabilities.nix
                                                   }
formatter.${system}                      1 line   → flake-parts/formatter.nix
checks.${system}                       358 lines  → flake-parts/checks/{
  statix                                 ~6 lines    → flake-parts/checks/statix.nix
  deadnix                                ~5 lines    → flake-parts/checks/deadnix.nix
  format                                 ~5 lines    → flake-parts/checks/format.nix
  lint (TOML registry dispatcher)       ~12 lines    → flake-parts/checks/lint.nix
  routing-coherence                     ~18 lines    → flake-parts/checks/routing-coherence.nix
  every-service-has-backup-intent       ~40 lines    → flake-parts/checks/services-have-backup.nix
  every-service-has-fs-hardening        ~55 lines    → flake-parts/checks/services-have-hardening.nix
  e2e-pi-smoke                           ~1 line     → flake-parts/checks/e2e-pi-smoke.nix
  e2e-multi-host                         ~1 line     → flake-parts/checks/e2e-multi-host.nix
  e2e-restic-backup                      ~1 line     → flake-parts/checks/e2e-restic-backup.nix
  e2e-disk-alert                         ~1 line     → flake-parts/checks/e2e-disk-alert.nix
  eval-lanroute-customdns              ~10 lines    → flake-parts/checks/eval-lanroute-customdns.nix
  eval-lanroute-port-validation        ~10 lines    → flake-parts/checks/eval-lanroute-port-validation.nix
  eval-route-invariants                ~10 lines    → flake-parts/checks/eval-route-invariants.nix
  eval-gatus-probes                    ~10 lines    → flake-parts/checks/eval-gatus-probes.nix
  docs-fresh                            ~45 lines    → flake-parts/checks/docs-fresh.nix
                                                   }
```

Resulting `flake.nix`:

```nix
{
  description = "nori infrastructure (NixOS) — workstation and future lab hosts";
  inputs = { … all 150 lines as today, plus flake-parts.url = "github:hercules-ci/flake-parts"; };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];   # add x86_64-darwin if mac homeConfig wants to ride here

      imports = [
        ./flake-parts/machines.nix
        ./flake-parts/home.nix
        ./flake-parts/devshell.nix
        ./flake-parts/formatter.nix
        ./flake-parts/packages/docs-lan-route.nix
        ./flake-parts/packages/docs-topology.nix
        ./flake-parts/packages/docs-capabilities.nix
        ./flake-parts/checks/statix.nix
        # …13 check imports…
      ];
    };
}
```

~40 lines. Each imported file is a self-contained flake-module declaring its piece of the outputs.

## Why this fits the homelab

| Alignment | Detail |
|---|---|
| **One construct per problem** (CLAUDE.md) | Each check / package / devshell becomes one file with one job. Today, two checks ~600 lines apart in the same file is a coupling artifact. |
| **`nori.<X>` philosophy** | flake-parts modules and `nori.<X>` modules are structurally the same shape (Reader = options/declarations; Writer = generated outputs). The mental model carries over. |
| **Audit finding #9 (flake.nix bloat)** | Direct resolution. 1055 → ~40 in the entry point. |
| **Audit findings #3, #4, #7** | Adding the next check becomes "drop a new file" instead of "diff against the 1055-line file". |
| **Push-gate review ergonomics** | Per-check diff is per-file, not interleaved in one mega-diff. |

## Why full dendritic does NOT fit

Two specific frictions:

### 1. Auto-import vs explicit routing

Your `CLAUDE.md` § "Docs map" routes agents + operators by **explicit path**: "USE WHEN topic X → read `docs/reference/<topic>.md`". The dendritic philosophy ("Nix files are automatically imported; no literal path imports") wins discoverability for *the Nix file* but costs discoverability for *where an output came from*.

Concrete: today, if `nix flake check` reports a failure in `every-service-has-fs-hardening`, the operator runs `grep -n 'every-service-has-fs-hardening' flake.nix` → finds it at line 868. With dendritic auto-import, the same grep needs to walk a directory tree. With flake-parts + explicit imports, the import list in `flake.nix` points directly at the file.

The explicit-import flake-parts shape preserves your "explicit-routing" CLAUDE.md style; auto-import dendritic doesn't.

### 2. Second indexer over `modules/`

Your `nori.lint`, `every-service-has-fs-hardening`, `every-service-has-backup-intent`, and `routing-coherence` checks all walk `modules/` with glob + grep. They expect a stable file layout under `modules/services/*.nix` and `modules/infra/*/default.nix`.

If you adopt haumea or `import-tree` for the flake-parts side, you'd have TWO indexers walking the source tree: one for Nix outputs (auto-import), one for lint scans (your existing globs). Conflicts: a file added under `flake-parts/checks/` would be picked up by haumea but ignored by your lint glob — fine. A file added under `modules/` would be picked up by both — fine as long as the schemas don't collide.

The risk is low but real, and the value (auto-import for `flake-parts/`) is small compared to explicit imports. flake-parts handles fine without haumea.

## Migration phasing (if you decide YES on flake-parts)

Suggested PATH: `paths/PATH-flake-parts-refactor.md` with these phases:

```
PHASE 1 — Foundation (CI green at each commit)
  1a. Add flake-parts input, wrap existing outputs in mkFlake { … }
      with everything still inline. Single commit; no behavioral change.
  1b. Pull `mkNixdocSection` + `mkFileDocstring` out to lib/nixdoc.nix
      (the "half-measure" from audit finding #9, but as a stepping stone).

PHASE 2 — Easy migrations (one commit per file, CI green)
  2a. formatter → flake-parts/formatter.nix
  2b. devshell → flake-parts/devshell.nix
  2c. machines + home → flake-parts/{machines,home}.nix

PHASE 3 — Packages (one commit per derivation)
  3a. docs-lan-route → flake-parts/packages/docs-lan-route.nix
  3b. docs-topology → … (same shape)
  3c. docs-capabilities → … (same shape)

PHASE 4 — Checks (the bulk; 13 files; one commit per file)
  4a-l. Each check → flake-parts/checks/<name>.nix
        Easy ones first (e2e-*, eval-*), then the bigger ones
        (every-service-has-*, lint, docs-fresh).

PHASE 5 — Verify
  5a. Compare `nix flake show .` before / after — output set is byte-identical.
  5b. Run `nix flake check` cold (no cache); compare to before-times.
  5c. Update CLAUDE.md § "Quality gates" to reference the new file layout.
```

CI green at every phase = each phase pushable independently. Worst-case rollback is one phase.

## Risks

| Risk | Mitigation |
|---|---|
| flake-parts eval semantics differ subtly from manual `system =` (perSystem transposition) | Verify with `nix flake show .` byte-for-byte before / after; CI gates catch divergence at every phase. |
| `inputs.self` references inside check derivations resolve differently inside `perSystem` | Same-file check at end of each phase. The `sops` fix commit `be3f0b4` already established the `inputs.self` pattern; it'll survive the move. |
| Adds `flake-parts` as a foundational dep (must-know for new contributors) | One paragraph in CLAUDE.md § "Quality gates" + a single example file (`flake-parts/checks/format.nix`) used as the exemplar. The pattern is mature, well-documented at flake.parts, low surprise. |
| `nixosOptionsDoc` declarations.declarations path-stripping (lines 348-358) depends on knowing the `inputs.self.outPath` — works under perSystem but verify | Same byte-compare approach. |
| Per-host channel pivots (D-C original framing) — does this enable workstation on master while mac stays on 26.05 cleanly? | YES, flake-parts makes it slightly cleaner via per-host flake-modules overlaying packages selectively. But you can already do this today via the `import nixpkgs-master { ... }` pattern (just landed in modules/home/claude-code/default.nix). Not a NEW capability, just a tidier home. |

## Decision matrix

```
Pick FULL dendritic (auto-import) when:
  - You want "drop a file to add an output" ergonomics over discoverability.
  - You're comfortable with two-indexers-over-source.
  - You're starting fresh (no existing modules/ to integrate with).

Pick FLAKE-PARTS ONLY (explicit imports) when:
  - You want the decomposition benefits without the philosophy change.
  - Your existing tooling expects stable, explicit file paths.
  - You want incremental migration with CI green at every step.

Pick STATUS QUO when:
  - flake.nix isn't actively painful.
  - You're not planning to add ≥3 new outputs in the near future.
  - You'd rather invest the 1-2 day budget elsewhere (audit findings #1-4 etc).
```

## Trigger to pick flake-parts now (operator answers)

1. *"I avoid editing flake.nix when I could because scrolling 1055 lines is annoying."* → YES.
2. *"I have 3+ new outputs planned in the next month (checks for the promotion register, generated docs for nori.{backups,fs,replicas}, layer-2 nixosTests for stateful services)."* → YES.
3. *"I'd rather just land audit findings #1-4 in the current structure and see if the bloat actually compounds."* → DEFER + land the half-measure (lib/nixdoc.nix extract) instead.

## Composability with the active audit work

If YES on flake-parts:
- Bundle Phase 1 (foundation) with the next routine flake.nix edit (one less yak-shaving session).
- Land audit findings #1+#2+#3 (the test coverage bundle) AFTER Phase 4 — those become "add three new files under flake-parts/checks/ and the Justfile recipes" instead of "diff into the 1055-line file".
- Land audit finding #4 (systemd-execstart-resolves) into the new structure — natural fit.

If DEFER on flake-parts:
- Extract `lib/nixdoc.nix` as the half-measure (shrinks flake.nix by ~150 lines).
- Add audit findings inline as today.
- Revisit when finding #7's three new generated-doc derivations are on the table (that's the inflection point — 3 new outputs justify the refactor).

## Open questions for the operator

1. **flake-parts version pinning** — pin to a release tag or follow `main`? Suggest pinning to a release (the project ships them; `v0.X.Y`).
2. **per-host channel pivots** — is this a NEAR-TERM driver (workstation on master soon?) or theoretical-future? If near-term, flake-parts makes the cleaner foundation.
3. **Mac homeConfigurations** — currently lives outside `nixosConfigurations`; flake-parts handles both via the same `flake` attribute. No change needed, but worth confirming the migration preserves Mac switch behavior.
4. **Auto-format on commit** — your `nixfmt-tree` formatter would still run on the new flake-parts/ tree; verify treefmt config handles the new directory.

## Recommended next step

Either:
- (A) **Decide now**: pick one of the three tiers. If flake-parts, I'll write `paths/PATH-flake-parts-refactor.md` (~5 phase doc following this evaluation's structure) so an executor can land it incrementally.
- (B) **Defer**: land audit findings #1-4 in the current structure; revisit dendritic / flake-parts when adding the generated-docs (finding #7) crosses the "3 new outputs" trigger.

Either choice is defensible. The status quo isn't a bug.
