---
summary: "Bundle plan for /improve audit findings #1+#2+#3 — close the silent-drift gap on `nori.harden` and `nori.fs` by adding the two missing layer-3 runtime introspection recipes, then mechanize the meta-rule (`infra-concerns-have-tests`) so future `modules/infra/<X>/` additions can't silently land without their test recipe. Two recipes prove the convention; the check then enforces it. Ordered to give immediate value (#1, #2) before the meta-step (#3)."
status: PLAN — awaiting execution
target_commit: 125a07f
audit_source: docs/plans/2026-06-21-improve-audit.md § findings #1, #2, #3
---

# Plan — infra concern test coverage (bundle: audit #1 + #2 + #3)

## Why bundled

The three findings share a single insight: **every Reader+Writer-shaped concern in `modules/infra/` needs a runtime introspection recipe**, and the convention should be a CI gate not prose. Writing the two missing recipes first (#1, #2) proves the pattern; the meta-check (#3) then ratchets it.

Executing the meta-check before the recipes exist would either red-flag the codebase on every CI run (annoying) or require a temporary allowlist (debt). The natural order is: build the convention, then enforce it.

## Phase 1 — `test-harden` recipe

### Why

`nori.harden.<unit>` is declared by every service module (enforced by `every-service-has-fs-hardening` flake check), but no recipe verifies the declaration actually lands in the running unit's `serviceConfig`. Silent drift: someone writes `protectHome = true` but a higher-precedence `mkForce` overrides it; or `binds = [pathA]` but a refactor of `nori.fs` changed `pathA`'s value mid-flight. Today these are caught only by service breakage during operator usage.

Sibling recipes for reference shape: `Justfile § test-backups` (restic snapshot freshness ≤25h), `Justfile § test-routes` (Caddy + DNS + HTTPS per declared route).

### What

Recipe location: `Justfile`, alphabetic among existing `test-*` recipes (between `test-eval` and `test-hypr`).

Recipe shape (mirroring `test-backups`):

```
@test-harden:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "→ test-harden: declared nori.harden.<unit> ↔ live systemd serviceConfig"

  # Tier 1: extract declared {unit → {ProtectHome, ProtectSystem, BindPaths, ReadOnlyBindPaths}}
  # from `nix eval` over config.nori.harden, output as one JSON line per unit.

  # Tier 2: for each declared unit, `systemctl show <unit> -p <Property>` and
  # compare each Property's live value to the declared value. Fail on mismatch.

  # Tier 3 (optional, future): assert the bind targets actually exist on disk
  # (so a typo in `binds = [...]` doesn't silently no-op).
```

### Done criteria

- [ ] `just test-harden` exits 0 on a green homelab with at least one declared `nori.harden.<unit>`.
- [ ] Manually flip one `protectHome = true` → `false` (or a `binds` path), rebuild, run `just test-harden`, observe RED with the specific unit + property + (declared, live) pair in the failure message.
- [ ] Revert; `just test-harden` green again.
- [ ] Recipe added to the `test-all` composite at `Justfile:181-188`.
- [ ] Cite this finding in `docs/invariants.md` § "Live `nori.<X>` enforcement — worked example" — `nori.harden` row's "Runtime introspection" column goes from empty to `[runtime-introspection: just test-harden]`.

### Out of scope

- Per-unit "did the unit actually start" check — that's a different concern (would belong in a generic `test-services` or in the existing `e2e-pi-smoke` nixosTest).
- Validation of `nori.harden.<unit>.capability` declarations — capabilities sit in a different namespace; deferred to `test-capabilities` if it lands later.

### Effort: S–M (half day)

The eval-side extraction is mechanical (one `nix eval --json`); the systemd-side reading is one `systemctl show -p` per property per unit; the comparison + failure-reporting is bash-pattern from `test-backups`. No new dependencies.

### Risk: LOW

Adds a query-only test; no code changes to the modules being tested. Worst-case false positive triggers refinement of the comparison logic.

---

## Phase 2 — `test-fs` recipe

### Why

`nori.fs.<n>` declares named filesystem locations with value-tier metadata; consumed by service modules and backup generators. Silent drift: path declared in `nori.fs.photos` but the disko subvolume actually mounts elsewhere; owner/mode mismatch between declaration and what tmpfiles applies; missing entry in `nori.backups` for a high-tier path.

`docs/reference/runtime-tests.md` already names this as a "next potential test target" with four-lever score `leverage 3 · volatility 1 · opacity 3 · blast 4`.

### What

Recipe shape:

```
@test-fs:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "→ test-fs: declared nori.fs ↔ live filesystem state ↔ backup coverage"

  # Tier 1: nix eval config.nori.fs → JSON of {name, path, owner, mode, tier}
  # Tier 2: for each entry, stat the path on disk — assert existence, owner, mode,
  # and (where mounted on btrfs) subvolume membership via `btrfs subvolume show`
  # Tier 3: cross-product against config.nori.backups — assert that every
  # nori.fs entry with tier="irreplaceable" or "high" has either:
  #   * an entry in nori.backups that includes its path, OR
  #   * an explicit nori.fs.<name>.skipBackup = "reason" annotation
```

### Done criteria

- [ ] `just test-fs` exits 0 on a green homelab.
- [ ] Manually rename a declared path on disk, rerun, observe RED with name + (declared, found) pair.
- [ ] Manually remove an irreplaceable-tier path from `nori.backups`, rerun, observe RED with "uncovered tier-irreplaceable path: …" message.
- [ ] Recipe added to `test-all` composite.
- [ ] `docs/invariants.md` updated similar to Phase 1.

### Out of scope

- Cross-host fs verification (per-host execution only; cross-host coverage lives in `test-replicas`).
- Subvolume reflink / snapshot freshness — covered by `test-backups`.

### Effort: S (couple hours)

Smaller surface than `test-harden` (no systemd-property reading). Pure `stat` + `btrfs subvolume show` + JSON cross-product.

### Risk: LOW

---

## Phase 3 — `infra-concerns-have-tests` flake check

### Why

Without a CI gate, every new `modules/infra/<X>/default.nix` is a silent commitment to ship a `test-<X>` recipe — but the commitment is enforced only by reviewer attention. The two recipes from phases 1 + 2 are the first time the convention is fully realized; this phase ratchets it so the convention can't backslide.

Pattern precedent: `every-service-has-fs-hardening` + `every-service-has-backup-intent` are exemplars. Both walk `modules/services/*.nix` with grep + a case-pattern exemption list and fail the build on uncovered modules.

### What

Add to `flake.nix § checks.${system}` — a new derivation following the exemplar shape:

```nix
infra-concerns-have-tests = pkgs.runCommandLocal "infra-concerns-have-tests" {
  nativeBuildInputs = [ pkgs.gnugrep pkgs.findutils ];
} ''
  cd ${./.}
  fail=0

  # Identify Reader+Writer-shaped infra concerns: a default.nix that declares
  # `options.nori.<name>` (a Reader schema). Pure import-aggregator modules
  # (no options.nori.* declaration) are exempt.
  for f in $(find modules/infra -maxdepth 2 -name 'default.nix' | sort); do
    if ! grep -qE 'options\.nori\.' "$f"; then continue; fi  # not Reader-shaped

    # Concern name = parent directory name (e.g. modules/infra/backup → "backup")
    concern=$(basename "$(dirname "$f")")

    # Expect a `test-<concern>` recipe in the Justfile.
    if ! grep -qE "^@?test-${concern}:" Justfile; then
      echo "✗ modules/infra/${concern}/ declares options.nori.* but Justfile"
      echo "   has no test-${concern} recipe."
      fail=1
    fi
  done

  if [ $fail -eq 0 ]; then
    touch $out
  else
    echo
    echo "Every Reader-shaped infra concern needs a runtime introspection recipe."
    echo "See docs/reference/runtime-tests.md § 'Four levers' for the framework."
    exit 1
  fi
'';
```

### Done criteria

- [ ] `nix flake check` passes with phases 1 + 2 landed (i.e. `test-harden` and `test-fs` recipes exist).
- [ ] Manually remove the `test-harden:` line from `Justfile`, run `nix flake check`, observe RED with `✗ modules/infra/capabilities/ declares options.nori.* but Justfile has no test-capabilities recipe.` — wait, the concern is `capabilities` not `harden`. Document this in the check: the test name = directory name, NOT the registry name. (i.e. `modules/infra/capabilities/` ⇒ `test-capabilities`, not `test-harden`. Decide.)
- [ ] Revert; `nix flake check` green.
- [ ] Update `docs/invariants.md § promotion work-list`: mark `infra-concerns-have-tests` as `✓ promoted` (alongside `disko-uses-by-id` and `function-named-subdomains`).
- [ ] Update `docs/roadmap.md § promotion register` table: same.

### A subtle naming question to resolve in this phase

The check needs to decide: should the recipe name match the **directory** (`test-capabilities`, `test-storage`) or the **registry namespace** (`test-harden`, `test-fs`)? Today's phases 1 + 2 chose the registry-namespace name (`test-harden`, `test-fs`). The directory-name choice would be `test-capabilities`, `test-storage`.

Pros of registry-namespace (current): names what you'd grep for in service modules (`grep nori.harden`).
Pros of directory-name: matches the auto-discovery the check does (`modules/infra/<dirname>`).

**Recommendation**: registry-namespace names (matches the data; the check derives the expected recipe name via a small lookup table inside the derivation). Decide before implementing the check; document the chosen rule in `docs/reference/runtime-tests.md`.

### Out of scope

- Other rungs (eval-time module assertions, prose comments) — those don't need a recipe.
- `modules/services/<X>.nix` test coverage — that's a different concern (see `infra-concerns-have-tests` direction item D-B in the audit).

### Effort: M (one day)

Bulk of the work is the lookup table (Reader registry → expected recipe name) + integration test (toggle a recipe, observe red, restore, green).

### Risk: LOW

The check is read-only over the source tree. Worst case is a false positive on an infra concern we forgot to add to the lookup; that's caught by the check itself and easily fixed.

---

## Execution order

Phases are dependency-ordered: Phase 3 will fail without phases 1 + 2 already landed. Suggested commit shape:

- Commit 1: `feat(testing): test-harden recipe — runtime introspection for nori.harden`
- Commit 2: `feat(testing): test-fs recipe — runtime introspection for nori.fs + backup coverage`
- Commit 3: `feat(lint): infra-concerns-have-tests — promote prose → law`

Each commit can be reviewed + pushed independently; CI green at every step.

## What this does NOT cover

The audit's finding #4 (`systemd-execstart-resolves`) is the OTHER outstanding promotion register item. It's a separate plan (different check shape — eval-time introspection over `config.systemd.services.*` instead of grep over source). If you're landing the promotion register completion as a single arc, this plan + a sibling for #4 + a `paths/PATH-promotion-register-completion.md` index would be the shape. Per the audit, that's option D-A.

## Escape hatches

- If Phase 3 reveals an infra concern that legitimately doesn't fit Reader+Writer (e.g. `modules/infra/motd.nix` is just a single string), add it to a documented exemption list in the check, mirroring the `baseNonServicePatterns` pattern at the top of `flake.nix § checks.${system}`.
- If `test-harden` or `test-fs` turn out to need privileged operations (CAP_SYS_ADMIN for btrfs introspection on aurora's encrypted volume), they may need to run via a polkit rule or be gated by a `sudo -n` check that gracefully degrades. Document in the recipe header; don't silently skip.

## Maintenance note

Future infra concerns will inherit this convention automatically — adding a new `modules/infra/<X>/` with a Reader schema = adding `just test-<X>` (otherwise CI fails). That's the goal.

Schema changes to `nori.harden` or `nori.fs` will need recipe updates (since the recipes encode the expected serviceConfig properties / fs metadata fields). The recipes should `nix eval` for the schema at runtime so they tolerate option additions automatically; only renames or semantic changes require recipe edits.
