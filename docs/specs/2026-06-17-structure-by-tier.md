---
date: 2026-06-17
status: spec — not in execution
seed: Stage 2 R3 deliverable; restructure recon from K6 audit + R1/R2 findings
summary: Reorganize modules from shape-based (effects/, services/) to tier-based (packages / services / distributed-services) with concerns cleaving WITHIN tiers. Prerequisite for several downstream generators (diagrams-from-code, location-policy extraction, drives-table-from-disko, resource-caps aggregation).
---

# Structure-by-tier restructure (spec seed)

Operator framing (paraphrased from session 2026-06-17):

> "It's almost tiered. Packages are stateless bundles of concern. Services are stateful. Packages are easily divisible / distributable. Distributed stateful services is where the complexity lives."

> "Storage policy is described in docs but dumped into modules/effects by category instead of by concern. Could be useful to group by concern, coupling, and by function."

## The structural mismatch

Today, modules are organized by SHAPE (what they look like syntactically), not by CONCERN (what question they answer):

```
modules/infra/      Reader/collected-Writer schemas (the SHAPE)
  ├── lan-route.nix       routes + access + location
  ├── backup.nix          backup intent
  ├── replication.nix     btrbk send/receive policy
  ├── fs.nix              fs-hardening shape
  ├── harden.nix          systemd hardening
  ├── gatus-probe.nix     probe surface for routes
  ├── gpu.nix             GPU device SoT
  ├── hosts.nix           topology registry
  ├── service-placement.nix  workhorse/appliance assertions
  ├── resource-tiers.nix     memory tier defaults
  ├── restart-policy.nix     restart-on-failure shape
  └── tailnet-appliance.nix  appliance hardening

modules/services/     Per-service modules (the SHAPE)
  ├── arr/                  *arr stack subgroup
  ├── backup/               backup engines (restic + btrbk + verify)
  ├── beszel/               beszel hub + agent split
  ├── (rest)                30+ per-service modules
```

Docs are organized by CONCERN (the question being answered):

```
docs/reference/
  ├── topology.md           "where does what run + why"
  ├── storage.md            "how is data laid out + backed up"
  ├── network.md            "how do clients reach services"
  ├── services.md           "how do I add a service"
```

To write `storage.md`, the docs author walks `effects/fs.nix` (subvol shape) + `effects/backup.nix` (backup intent) + `effects/replication.nix` (replication policy) + `services/backup/*.nix` (engines). FOUR module surfaces for ONE concern.

To write `network.md`, the author walks `effects/lan-route.nix` (route registration) + `effects/gatus-probe.nix` (probe surface) + `services/caddy.nix` (HTTP proxy) + `services/authelia.nix` (OIDC) + `services/blocky.nix` (DNS). FIVE module surfaces for ONE concern.

This is why the K6 audit found cross-effect sections (service placement, drives, GPU, caps) resist co-location. No single module owns the question.

## Proposed tier structure

```
tier              what it is                  examples
─────────────────────────────────────────────────────────────────
packages          stateless code              upstream nixpkgs;
                  bundles of concern;         dev fragments;
                  freely composable           home.packages
                  (no state binding)          (firefox, vlc)

services          stateful                    vaultwarden (sqlite),
                  local to one host           navidrome (sqlite),
                  ⇒ location IMPLICIT         calibre-web (sqlite),
                  ⇒ backup intent attached    radicale (filesystem)
                  ⇒ may expose lan-route

distributed       stateful                    immich (server +
services          spanning multiple hosts     ml + db, cross-host);
                  ⇒ location EXPLICIT         beszel (hub on pi,
                    via runsOn                  agent everywhere);
                  ⇒ algebraic forward-shape   ntfy (server on pi,
                    (failover/loadbalance/      notify-client
                    sequential) lives here     everywhere);
                                              btrbk (replication
                                              between hosts)
```

Within each tier, modules cleave by CONCERN, not by shape:

```
services/<service>/         per-service folder
  ├── default.nix             intent + opt-in toggle
  ├── storage-policy.nix      fs subvols, backup tier, value tier
  ├── access-policy.nix       lan-route, audience, OIDC, monitor
  ├── observability.nix       scraped, alerted, dashboarded
  └── (engine-specific)       package, port, runtime config
```

This means `nori.lanRoutes.<X>` no longer lives in `effects/lan-route.nix` as a SCHEMA divorced from the services that use it — instead, each service's `access-policy.nix` declares its route inline, and the lan-route DSL becomes a thin utility module that defines the option type (not the place where instances live).

```
WAS                                     IS
────────────────────────────────────────────────────────────────
effects/lan-route.nix                   lib/lan-route.nix
  options.nori.lanRoutes (schema)         option type definition
  config (collected generators)           generator functions

  ↓ collected from anywhere                ↓ called by access-policy
                                             modules per service
services/vaultwarden.nix                services/vaultwarden/
  options.services.vaultwarden            ├── default.nix
  config.nori.lanRoutes.vault =             │   options + opt-in
    { ... }                                 ├── storage-policy.nix
                                             │   nori.fs.vault-sqlite
                                             ├── access-policy.nix
                                             │   nori.lanRoutes.vault
                                             └── observability.nix
                                                  scrape + dashboard
```

## What this unlocks

```
1. Diagrams-from-code (R1)
   Walking `services/*/access-policy.nix` collects all proxy edges
   in one pass; walking `services/*/observability.nix` collects
   all scrape edges; walking `services/*/storage-policy.nix +
   services/<*>/.../backup-target` collects all backup edges.
   ⇒ Topology diagram generator becomes one function.

2. Drives table from disko (K6 deferred)
   Walking `services/*/storage-policy.nix` references concrete
   disko subvols, which already know their drive + label.
   ⇒ Drives table = group disko devices by drive, render rows.

3. Resource caps aggregation (topology.md table)
   Walking `services/*/default.nix` for `cap = { value; reason; }`
   collects rationale. ⇒ Caps table = generator output.

4. Location-policy extraction (R2)
   `services/*/access-policy.nix` declares route, which contains
   runsOn — extraction is "lift runsOn out of nori.lanRoutes
   schema into a sibling option." Or stays coupled per R2 (γ).

5. Service-placement table
   Same as #1 — placement = walking all services and grouping
   by access-policy.runsOn.

6. Storage / network / services .md files shrink dramatically
   Each becomes "the WHY + curated overview"; the WHAT moves
   under generated artifacts per concern.
```

## Risk + cost

```
risk                                   mitigation
──────────────────────────────────────────────────────────────
Breaks every service module's          Migrate one service at a
existing shape (single .nix file).     time as a pilot; the
                                       existing nori.lanRoutes
                                       option absorbs both shapes
                                       (the schema is the same).

Increases module count from ~50 to     Per-service folder is more
~200 if every service grows 4 files.   discoverable than nesting
                                       four concerns in one file;
                                       grep gets less useful, ls
                                       gets more useful.

Adds folder navigation to per-service  Each per-service folder
authoring vs single-file.              has default.nix as entry
                                       point; nix's `imports`
                                       handles the rest.

Drift between concern files and        Same fan-in collection
intent.                                pattern as today — module
                                       system enforces wire-up.

Path of "what changed?" in git log     Per-concern commits
gets noisier per-service (4 files).    (e.g. "vaultwarden:
                                       observability — add
                                       dashboard") become finer-
                                       grained and more legible.
```

## Adoption sequencing (not in scope of this spec)

```
Phase 0  This spec lands; operator confirms direction.

Phase 1  Pick a pilot service — small surface, clean concern
         separation. Candidate: `vaultwarden` (sqlite local,
         lan-route'd, OIDC-gated, backed up; 4 concerns are
         clean).

Phase 2  Migrate pilot service: vaultwarden.nix splits into
         vaultwarden/{default,storage,access,observability}.nix.
         Verify checks pass; no behavioral change.

Phase 3  Codify the per-service folder shape in
         module-authoring.md; pick second pilot. Validate
         the shape generalizes.

Phase 4  Bulk migration of remaining services in a structured
         order: family-tier first (aurora), then workstation
         tier (mostly arr stack), then pi (entry plane).

Phase 5  Each generator (diagrams, drives, caps) lands as a
         separate sprint after the relevant tier-of-modules
         has migrated.

Phase 6  effects/ thins out as schemas-only or moves under lib/.
         services/ becomes the home of all service declarations
         in per-service folders.
```

## Out of scope of this spec

- effects/ → lib/ rename (Phase 6+)
- The R1 D2 diagram generator (Phase 5+)
- The K6 drives table generator (Phase 5+)
- The R2 location-policy extraction (still rule-of-three deferred)
- Conversion of the homelab's own dev-shell composer / Stage 1 doc-comment convention (already lands cleanly per existing module shape)

## Decision needed before Phase 1

```
1. Folder-per-service shape — confirm 4-concern split (storage /
   access / observability / engine) vs 3-concern (storage /
   access / engine, with observability absorbed by access).

2. Path-naming inside per-service folder — `default.nix +
   storage-policy.nix + access-policy.nix + observability.nix`
   vs flatter (`vaultwarden/storage.nix + access.nix + ...`).

3. Migration cadence — one-PR-per-service vs batch (e.g. all
   aurora-tier in one PR).

4. Whether to land the diagram generator (R1 follow-on) in this
   restructure arc or as a Phase 5 follow-up.
```

## Connection to the Stage 2 verdict

This spec is the answer to "structure-by-tier is the followup if the convention earns adoption." Stage 2 (K2–K6) established the convention scales for config-dump sections; this spec is what unblocks the cross-effect sections.

K7 records the verdict: keep the convention, commit to this restructure as the follow-on.
