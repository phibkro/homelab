---
date: 2026-06-17
status: spec — not in execution
seed: operator framing 2026-06-17 (after modules-as-root restructure landed); absorbs 3 forward items (workhorse-vs-appliance-placement law, R2 runsOn algebraic extension, K6 macbook-registry gap)
summary: Reshape `nori.hosts` from identity-heavy registry to a capability-flag schema. Machines declare WHAT THEY ARE (compute capabilities + role) and services declare WHAT THEY NEED. A placement resolver matches services to machines; eval fails if no match. Unifies the host/agent/client/appliance distinction, includes the macbook (currently absent), and primes the codebase for typed multi-host runsOn (failover / load-balance / sequential).
---

# Machine capabilities (spec)

## Why

```
problem                                  symptom
─────────────────────────────────────────────────────────────────
"host" is overloaded                     the verb (X hosts Y), the
                                         noun (tailnet host), and
                                         "compute resource I run
                                         workloads on" all conflate.
                                         New agents trip on this.

nori.hosts schema is identity-           tailnetIp / lanIp / codename
heavy; capability-light                  / hardware (free-text) /
                                         primaryJob (free-text) /
                                         role (enum). No typed
                                         capability flags. Services
                                         can't ASK for what they
                                         need.

placement.nix is negative-only           assertions say "this role
                                         can't do that" but never
                                         "this service needs X
                                         capability; find a host
                                         with X." Drift class:
                                         services land on hosts
                                         that incidentally work
                                         until they don't.

macbook is in identityFor's              the K6 audit named it; the
COMMENT but not in the registry          tier-principle codification
                                         in topology.md routed around
                                         it. Inconsistent.

tailnet devices (chromecast,             they're real network
pixel, printers) aren't in code          participants; the codebase
                                         pretends they don't exist.
                                         Documenting them as machines
                                         lets blocky / Caddy access
                                         policy be eval-checked
                                         against them.

R2 algebraic runsOn extension            failover/loadbalance/
needs a capability registry              sequential needs to ask
                                         "which hosts have X capa-
                                         bility?" to pick candidates.
                                         No such registry exists.
```

## The mental model

```
Machines declare:    what they ARE.

  hosts             servers that run workloads
                    capability set: { serves; persistent }
                    examples: pi, aurora, workstation
                    
  agents            untrusted-compute quarantine
                    capability set: { serves(agent-only);
                                      ephemeral }
                    examples: pavilion
                    
  clients           consume-only devices
                    capability set: { connects }
                    examples: macbook, chromecast, pixel 8a,
                              printers

Within hosts, sub-shapes by capability:

  workhorse-host    GPU + state + always-on or sleep-friendly
                    (workstation: sleep-friendly compute,
                     aurora: always-on family vault)
                    
  appliance-host    always-on + anti-write storage +
                    survives-workhorse-failure
                    (pi: entry plane)

Services declare:   what they NEED.

  resource requirements   { gpu; state; alwaysOn; antiWrite; ... }
  placement preferences   { tier = "family" | "operator" | ...; }
  count                   how many machines should run it
                          (single | multi-failover | multi-LB)

The placement resolver matches services to machines:

  for each service:
    candidates = machines.filter(m => m.capabilities ⊇ service.requires)
    if candidates.empty:
      eval-fail with "no machine satisfies <requirements>"
    if service.count == 1:
      pick the one host that opts in (services.<X>.enable = true on
      that host) OR pick the most-constrained match
    if service.count > 1:
      pick N candidates by semantic (failover: ordered; LB: parallel)
```

This is the PaaS scheduler shape applied at eval time. k8s does it at runtime via nodeSelectors + taints + tolerations + scheduler. We do it at eval via Nix module assertions.

## Current code audit

```
present today                                what shape
─────────────────────────────────────────────────────────────────
modules/infra/hosts.nix                      schema (Reader)
  options.nori.hosts.<name>.{tailnetIp,
    lanIp, codename, hardware, primaryJob,
    roleOneLiner, role}

modules/machines/default.nix                 values
  identityFor (the 4 hosts' actual
  identity + role declarations)

modules/infra/placement.nix                  negative assertions
  - role="appliance" cannot use nori.backups
    with paths
  - role="agent" cannot use nori.backups at all

modules/services/<X>.nix                     ad-hoc tags
  nori.services.<X>.tags = [ "family-tier"
                              "stateful" ]

modules/services/<X>.nix                     activation flags
  nori.services.<X>.enable = true
  (per-host opt-in)

modules/infra/networking/default.nix         per-route location
  nori.lanRoutes.<X>.runsOn = "<hostname>"   pointing at a host
                                             (single, not capability-
                                              based)
```

```
missing                                       needed
─────────────────────────────────────────────────────────────────
typed capability flags on machines           gpu | state | alwaysOn |
                                             antiWrite | serves(-)
                                             | ephemeral

service requirement declarations             nori.services.<X>
                                             .requires =
                                             { gpu = true;
                                               alwaysOn = true; }

placement resolver                           matches requires to
                                             machine capabilities;
                                             emits assertions

client + tailnet-device representation       macbook + chromecast +
                                             pixel 8a as
                                             nori.machines.<X>
                                             with role="client"

unified naming                               machine vs host vs
                                             compute — pick one
```

## Open design questions

```
Q1   Naming: nori.hosts vs nori.machines vs nori.compute
     
     (α) nori.hosts          — keep; document "host" = "compute
                                resource" in glossary; minimal churn
     (β) nori.machines       — broader; covers clients/agents
                                naturally; clashes namespace-wise
                                with modules/machines/ folder
     (γ) nori.compute        — PaaS terminology; clear; new word
     
     Lean: (β) — the broader term is honest; the folder clash is
     namespace vs filesystem-path (different dimensions).
     modules/machines/ is the FACTORY; nori.machines is the
     REGISTRY. They reference different things.

Q2   Role enum shape: extend or replace?
     
     Today:    role = "workhorse" | "appliance" | "agent"
     Possible: role = "host" | "agent" | "client" | "appliance"
               + sub-tags per role
     OR:       drop the enum; just use capability flags
     
     (α) keep coarse enum + add fine-grained capabilities
         (role = "host" + capabilities = { gpu; alwaysOn; ... })
     (β) drop enum entirely; pure capability flags
         (alwaysOn = bool; gpu = bool; persistent = bool;
          untrusted = bool; clientOnly = bool)
     (γ) hybrid: 3 enum (host/agent/client) + capabilities per role
     
     Lean: (γ) — operators think in roles; the capability flags
     are what the resolver matches on. Both surfaces are useful.

Q3   Tailnet-device scope: include or opaque?
     
     chromecast / pixel / printers — they DO consume routes via
     blocky DNS + Caddy proxy. They DON'T run any Nix-declared
     config.
     
     (α) include as role="client" machines with minimal capability
         (just tailnetIp + audience hint)
     (β) leave opaque to Nix; document elsewhere
     (γ) include only the ones we care about for OIDC/audience
         eval-checks (pixel needs OIDC group access)
     
     Lean: (γ) — only include when the codebase wants to assert
     something about them.

Q4   Service requirement granularity
     
     (α) flat flags                requires.gpu = true;
                                   requires.alwaysOn = true;
     (β) typed enums               requires = [ "gpu" "alwaysOn" ];
     (γ) hierarchical              requires.compute.gpu = true;
                                   requires.lifetime.alwaysOn = true;
     
     Lean: (α) — flat is easier to extend, easier to read.

Q5   Service count + multi-host
     
     Today: nori.lanRoutes.<X>.runsOn = "<single-host>"
     
     Forward (R2): runsOn = list + semantic-tag
                   ({hosts = [...]; semantic = "failover" | ... })
     
     Where does count belong? On the SERVICE (a service IS multi-
     host) or on the ROUTE (a route can be backed by multiple
     hosts)?
     
     Lean: route — matches R2's framing. The route IS the cross-
     machine surface.

Q6   Macbook treatment
     
     Macbook runs home-manager but no NixOS config; it doesn't
     have nori.* options visible.
     
     (α) Add it to nori.machines with role="client"
         empty capabilities, just identity (codename, tailnetIp,
         hardware string)
     (β) Add a nori.clients submodule under the home-manager
         flake (separate option family for non-NixOS devices)
     
     Lean: (α) — unified registry. Server-side eval can reason
     about macbook even when macbook itself doesn't eval it.

Q7   Migration path: replace or extend in-place?
     
     (α) Big-bang rename nori.hosts → nori.machines; update
         consumers across the tree in one atomic commit
     (β) Add nori.machines alongside nori.hosts; deprecate
         nori.hosts; migrate consumers gradually; remove
         eventually
     
     Lean: (α) — Nix-native rename + sed-update is mechanical;
     byte-equal verification catches semantic drift. The
     overlapping-period of (β) is more complex than the rename.

Q8   Replication.nix in this scope?
     
     Currently modules/infra/storage/replication.nix declares
     nori.replicas.<X>.{source, target}.host references. Those
     hosts would become machine references under the new schema.
     
     Lean: in scope. The replication registry IS placement-
     adjacent (it's "where does this data live across hosts").
```

## Migration phases (proposed; not in execution)

```
Phase 0 — Spec confirmation
  Operator confirms naming (Q1) + role-shape (Q2) + tailnet-
  device scope (Q3) + capability granularity (Q4) + macbook
  treatment (Q6) + migration shape (Q7).
  
  Specifically: rename nori.hosts → nori.machines? Or keep
  nori.hosts but extend? Decision unblocks the rest.

Phase 1 — Schema extension (additive, byte-equal)
  Add typed capability flags to the existing schema:
    nori.hosts.<name>.capabilities = {
      gpu = bool; default = false;
      state = bool; default = true;
      alwaysOn = bool; default = false;
      antiWrite = bool; default = false;
      ephemeral = bool; default = false;
      role = "host" | "agent" | "client" | "appliance";
        (or refactored per Q2)
    };
  Populate from existing identityFor values (workstation has
  gpu+state+sleep-friendly; pi has alwaysOn+antiWrite+appliance;
  aurora has gpu(weak)+state+alwaysOn+host; pavilion has
  ephemeral+agent).
  Byte-equal verified — nothing reads capabilities yet, just
  visible in option tree.

Phase 2 — Add macbook + tailnet devices in scope
  Per Q3+Q6 decisions. macbook joins nori.machines (or nori.hosts)
  with role="client" + capability set. Optional: chromecast +
  pixel if Q3 lands at (γ).

Phase 3 — Service requirement declarations
  Add nori.services.<X>.requires schema. Pilot on a few high-
  signal services:
    ollama        requires gpu
    immich-ml     requires gpu(weak ok)
    vaultwarden   requires alwaysOn + state
    gatus         requires alwaysOn (appliance survives outage)
  Other services keep empty requires{} for now; no enforcement
  yet.

Phase 4 — Placement resolver
  Build the resolver. For each service with non-empty requires:
    - find machines satisfying requires (capability ⊇)
    - assert at least one host opts in (.enable = true)
    - emit warning if multiple hosts opt in but service is
      single-count
  Eval fails on no-match. This is the workhorse-vs-appliance-
  placement promotion-register law.

Phase 5 — runsOn multi-host (R2 algebraic extension)
  nori.lanRoutes.<X>.runsOn type widens:
    string | { hosts = [...]; semantic = "failover" | "lb" | "seq"; }
  String form is sugar for { hosts = [s]; semantic = "failover"; }.
  Caddy generator + Gatus monitor + Blocky DNS adapt.

Phase 6 — Cleanup
  Remove the negative-only placement.nix assertions (subsumed by
  the resolver). identityFor in modules/machines/default.nix
  shrinks (capability flags move into the data).
  Topology-generated.md regenerated; documentation updates.
```

## Verification protocol

Same as modules-as-root restructure: byte-equal `nix eval` on
representative trees per phase; 9 flake checks pass at every
commit; representative hosts unchanged behaviorally for Phases
1-2 (additive). Phase 4 onwards is intentionally behavior-
changing (failing eval on requirement mismatch is the FEATURE).

## What this spec absorbs

```
roadmap promotion-register
  workhorse-vs-appliance-placement → law  becomes Phase 4's
                                          first user

specs
  R2 runsOn coupling analysis →           Phase 5
  algebraic runsOn extension

K6 audit
  macbook-in-registry gap →               Phase 2 fix
```

## Out of scope

```
- Capability INFERENCE from hardware (parse the hardware
  string for "RTX" → infer gpu=true). Capabilities are
  declarative; inference would be a separate enhancement.
- A separate runtime scheduler (we resolve at eval time,
  not deploy time).
- Client-side software-package declarations (macbook +
  pixel have apps; this spec is about CAPABILITY shape
  for placement, not about declaring what software runs
  on clients).
- Replacing tailscale ACL with Nix-derived ACL (interesting
  follow-on; not this spec).
```

## Connection to documentation-writing.md adoption table

```
Stage 1   convention codified           ✓
Stage 2   pressure test (topology.md)   ✓
Stage 2.5 modules-as-root restructure   ✓ Phases 0-3f landed
─────────────────────────────────────────────────────────────
Stage 3   generator extended            □ pending — Stage 3 uses
                                          the post-restructure
                                          shape; can land
                                          independently of this
                                          spec
Stage 4   content migration             □ pending — orthogonal
Stage 5   docs-fresh flake check        □ pending — orthogonal

This machine-capabilities spec is an ADJACENT arc, not within
the adoption table. It addresses a different problem (placement
intelligence) using the same restructured codebase as the
substrate.
```
