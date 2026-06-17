---
date: 2026-06-17
status: spec — not in execution
seed: operator framing 2026-06-17 ("move modules/common to modules/home and modules/desktop to modules/machines under base/. is that reasonable?"); refined after scope-distinction pushback.
summary: Consolidate NixOS-system-scope concerns under `modules/machines/` so the tree's TOP-LEVEL CUT mirrors the Nix module SCOPE (system vs home-manager). Today `modules/common/` and `modules/desktop/` are NixOS-system-scope but live at the top level alongside the home-manager-scope `modules/home/`; the conflation forces readers to know each subtree's scope by reading its content. Proposal: move `modules/common/` → `modules/machines/base/`, `modules/desktop/` → `modules/machines/desktop/`. After: `modules/machines/` IS the NixOS-system tree; `modules/home/` IS the home-manager tree; the scope distinction is structural.
---

# Scope-aligned tree consolidation (spec)

## Why

The modules-as-root restructure (Phase 0-4) landed a clear PaaS lens for `infra/<concern>/` and a clear workload tree under `services/`. But two siblings at the top level still violate the structural-scope-clarity principle:

```
current
─────────────────────────────────────────────
modules/common/        NixOS-system scope     ← imported by every host's
                                                modules/machines/<host>/default.nix

modules/desktop/       NixOS-system scope     ← imported by workstation only

modules/home/          home-manager scope     ← imported by each host's
                                                modules/machines/<host>/home.nix

modules/machines/      NixOS-system scope,    ← the host registry + per-host
                       per-host                 configs
```

A reader landing on the tree can't tell from folder names whether a given subtree is system-scope or home-manager-scope without opening files. The Nix module system has hard rules about which options exist in which scope; mixing the two at the top level forces the operator (and the agents) to track scope mentally.

```
problem                                  symptom
─────────────────────────────────────────────────────────────
"common" reads as "shared with             tells the reader nothing about
home-manager too"; really means            scope. Easy to mistakenly
"shared NixOS baseline"                    target it from a home-manager
                                           context.

modules/desktop/ (NixOS) sits next         "desktop" appears in two trees
to modules/home/desktop/ (HM) with         (modules/desktop, modules/home/
no structural cue                          desktop) — same word, different
                                           scopes. Discovery hostile.

every NixOS host imports                   the import is path-coupling:
../../modules/common (now ../../common     each host knows where common
post-Phase-4 layout) plus possibly         lives. Moving common changes
../../modules/desktop                      every host's import. The path
                                           drift is the cost of the
                                           current shape, not a feature.
```

## The cut

Move both NixOS-system-scope subtrees under `modules/machines/`. After:

```
modules/
  machines/            NIXOS-SYSTEM SCOPE — every subtree here is a
                       NixOS module
    base/                ← was modules/common/
      base.nix, users.nix, sops.nix, tailscale.nix, default.nix
    desktop/             ← was modules/desktop/
      apps.nix, audio.nix, fonts.nix, greetd.nix, gaming.nix,
      hyprland.nix, stylix.nix, sunshine.nix, virt.nix, default.nix
    default.nix          ← factory (unchanged shape; explicit imports
                           landed in Phase 5a)
    workstation/         ← per-host, imports ../base + ../desktop
    pi/                  ← per-host, imports ../base
    aurora/              ← per-host, imports ../base + ../services
    pavilion/            ← per-host, imports ../base (selective)
    macbook/             ← home.nix only (not a NixOS host)

  home/                HOME-MANAGER SCOPE — every subtree here is a
                       home-manager module
    core.nix             unchanged location (or → home/base/cross-platform.nix
                         if you want symmetry — open question Q1)
    pc.nix               unchanged location (or → home/base/linux-pc.nix)
    claude-code/         unchanged
    desktop/             unchanged — HM-scope desktop bits
    hermes/              unchanged
    default.nix          standalone home-manager factory

  infra/               PaaS infra modules (Reader+Writer concerns)
                       NIXOS-SYSTEM SCOPE — consumed by modules/machines/
                       hosts via the bundle import. Stays where it is;
                       lives at top level because it's the platform layer
                       that machines USE, not part of machines themselves.

  services/            Workload modules
                       NIXOS-SYSTEM SCOPE — same reasoning as infra/.
                       Stays at top level.
```

```
mental model after
──────────────────────────────────────────────────────────────
modules/machines/    = "what each compute resource declares about itself"
                       (base posture + role-specific concerns + per-host)
modules/home/        = "what each user surface declares about itself"
modules/infra/       = "the PaaS the machines plug into"
modules/services/    = "the workloads running on top"
```

Four trees, four clear semantics, no scope mixing.

## What this is NOT

```
✗ NOT moving modules/infra/ or modules/services/ under modules/machines/.
  Those are SHARED platform/workload trees that any machine can pull
  from via the bundle import; they're not "per-host" concerns. Keeping
  them at the top level reflects that.

✗ NOT promoting "common" to a more semantically loaded name like
  "baseline" or "shared". The rename is *to fit under modules/machines/*
  (becomes `base/` — short, contextually clear). Outside that scope
  the name carried no other improvement.

✗ NOT a behavioral change. Every import resolves the same module
  contents; only paths shift. Byte-equal nix eval against representative
  hosts proves no semantic drift.

✗ NOT touching modules/home/ contents (decision deferred — open Q1).
```

## The migrations

```
file moves (mechanical)
────────────────────────────────────────
git mv modules/common   modules/machines/base
git mv modules/desktop  modules/machines/desktop

import path updates (load-bearing)
────────────────────────────────────────
modules/machines/workstation/default.nix
  ../../common  → ../base
  ../../desktop → ../desktop
modules/machines/aurora/default.nix
  ../../common  → ../base
modules/machines/pi/default.nix
  ../../common  → ../base
modules/machines/pavilion/default.nix
  ../../common  → ../base
  ../../infra/observability/<X>  → ../../infra/... (unchanged depth)

lint rule scope updates
────────────────────────────────────────
lint/rules.toml `scope = ["modules/"]` rules already cover the new
tree (no scope-string change needed — modules/ stays the umbrella).

doc-comment + doc updates
────────────────────────────────────────
~30 prose refs to `modules/common/` → `modules/machines/base/`
~15 prose refs to `modules/desktop/` → `modules/machines/desktop/`
Generated docs (lan-route-options, topology-generated) regenerate.

generators
────────────────────────────────────────
flake.nix mkNixdocSection invocations unchanged (no entries point at
common/ or desktop/).
```

## Verification

```
gate 1   byte-equal nix eval of each host config
         nix-instantiate --eval -E '...' before/after
         hash compare
gate 2   nix flake check passes (8 checks)
gate 3   just check-migration passes (path-coherence script)
         — surfaces any stale doc-comments
gate 4   regenerate the 2 generated docs; commit-time diff is
         only changed paths, no content drift
```

## Goal / Constraints / Values

**Goal (verifiable):** every NixOS-system-scope concern in `modules/` lives under `modules/machines/` (excluding `infra/` and `services/`, which are platform/workload trees consumed by machines). Byte-equal nix eval against all 4 NixOS hosts. All 8 flake checks pass.

**Constraints (hard):**
- C1. No behavioral drift. Eval byte-equal before/after.
- C2. No `nix flake check` regression. 8 checks remain green.
- C3. Single commit per logical step (move + import update is one atomic op per concern).
- C4. modules/home/ contents NOT touched in Phase 6 (deferred — see Q1).

**Values (soft):**
- V1. Prefer name `base/` over alternatives; short, fits the new context, doesn't pretend to scope claims it can't make.
- V2. Prefer atomic per-concern commits (common → base, desktop → desktop) so each is independently revertable.
- V3. The migration is a discovery pass for stale doc refs; embrace the path-coherence script firing as a benefit, not a cost.

## Open questions

```
Q1   should modules/home/{core,pc}.nix move to modules/home/base/
     for symmetry with modules/machines/base/?
     → tradeoff: symmetry vs minimal-touch. modules/home/ doesn't
       suffer the scope conflation problem because there's only one
       scope (HM) in the subtree. The rename buys symmetry but no
       new clarity.
     → bias: NO. Keep modules/home/ flat. If a third HM tier emerges,
       reconsider.

Q2   should modules/machines/desktop/ move under modules/machines/base/
     as base/desktop/ (per operator's "under base/" framing)?
     → tradeoff: base/ becomes an aggregator (every host imports the
       whole base/ tree) or a folder of separate concerns (host
       imports base/ + base/desktop/ selectively).
     → bias: NO. base/ is the unconditional NixOS baseline; desktop/
       is conditional (workstation only). Putting desktop under base/
       conflates "every host gets this" with "some hosts get this".
       Keep desktop/ as a sibling.

Q3   should infra/ and services/ also move under modules/machines/?
     → tradeoff: scope-aligned (yes, they're NixOS-system-scope) vs
       layer-aligned (no, they're the platform-and-workloads layer
       that machines consume).
     → bias: NO. PaaS lens dominates here. machines USE infra +
       services; they don't OWN them. Top-level reflects that
       consume-vs-own distinction.

Q4   should the per-host folders inside modules/machines/ also get a
     scope marker (e.g. modules/machines/hosts/<host>/ wrapping the
     existing modules/machines/<host>/)?
     → tradeoff: extra nesting vs visual symmetry with base/ + desktop/.
     → bias: NO. The folder name IS the host name; nesting buys
       nothing semantic.

Q5   migration ordering: common-first or desktop-first?
     → bias: common-first. Smaller blast radius (every host imports
       it), so each post-move eval verifies all hosts in one step.
       desktop-first only verifies workstation.
```

## Phase ordering

```
phase 6a   modules/common → modules/machines/base/
           4 import updates (../../common → ../base) across hosts
           prose refs follow via bulk rewrite
           verify: byte-equal eval per host; flake check; check-migration

phase 6b   modules/desktop → modules/machines/desktop/
           1 import update (../../desktop → ../desktop) in workstation
           prose refs follow via bulk rewrite
           verify: byte-equal eval; flake check; check-migration

phase 6c   doc cleanup pass
           CLAUDE.md tier-overview update
           docs/glossary.md path refs
           docs/reference/module-authoring.md updated module-authoring shape
           docs/reference/topology.md if it references common/desktop
           any spec / report in docs/specs/ + docs/reports/ stays
           historical (path-coherence skip-file on those is already in
           place)
```

## Reversibility

Each phase is atomic and revertable via `git revert`. The moves are
`git mv` operations preserving history; the import-path edits are
small (4 hosts × 1 import line each for phase 6a; 1 host × 1 line for
phase 6b). Worst-case cost of revert: re-run two `git mv` commands
in reverse + revert the import edits. ~10 minutes.

## Predecessor / successor

- Builds on: Phase 4 (modules-as-root restructure), Phase 5a-d
  (explicit machine imports, modules/dev removal, lint extraction,
  migration-check pruning).
- Does not block: any current outstanding work. Pure refactor.
- Pairs naturally with: future Phase 7+ if `modules/home/` grows
  enough internal tiering to warrant its own scope-marker reorg.
