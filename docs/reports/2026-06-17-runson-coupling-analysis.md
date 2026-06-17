---
date: 2026-06-17
summary: R2 — runsOn coupling analysis. Is location-policy a separate concern wedged into lan-route, or legitimately part of route registration? Tier insight; algebraic extension; verdict.
---

# `runsOn` coupling analysis (R2)

Stage 2 recon. Operator framing: "currently its coupled with route registration as the runsOn option. should investigate if service registration, route registration, hosting location etc. is strictly coupled or loosely coupled and whether to co-locate options in a singular file or a folder."

## The three concerns (named)

```
service registration   "this service exists; ship its module if my
                       host wants it"
route registration     "this service exposes HTTP at this audience,
                       on this port, with these monitor/alert wires"
hosting location       "this service runs on host X (and the proxy
                       needs to know)"
```

`nori.lanRoutes.<X>.runsOn` answers ONLY the third. Today it's spelled inside the lan-route schema.

## The tier insight (load-bearing)

A service has a default location: **the host that imports it**. No declaration needed.

```
machines/aurora/default.nix imports modules/services/vaultwarden.nix
                                    ⇒ vaultwarden runs on aurora
```

Aurora's module list IS the location declaration. No `runsOn`, no cross-host wiring. The implication: when a service is host-confined, location is **implicit-from-import-site** and the three concerns degenerate to one (service-registration alone).

Location becomes EXPLICIT only at the moment the service crosses machines — i.e. when something on a non-running host needs to reach it. That something is, in this codebase, almost exclusively the entry-plane Caddy on pi. Crossing the machine boundary means HTTP exposure means lan-route. **Location-explicit is route-explicit, and conversely.**

This is why `runsOn` lives on `nori.lanRoutes`. Not by convenience. Because the act of exposing a service via HTTP IS the act of declaring that location must be resolved across the machine boundary.

```
                    declaration       state      location       cross-machine?
                    ─────────────────────────────────────────────────────────────
  packages          common module     none       anywhere       N/A
                    imports                                     (stateless)
  services          machines/<n>/     local      implicit-from- opt-in via
                    default.nix       (per       import-site    lan-route
                                      host)
  distributed       lan-route +       local +    EXPLICIT —     N/A
  services          runsOn            binding    runsOn host    (already is)
                                                 (today: 1
                                                 forward:
                                                 1..N + tag)
```

## Empirical check — 34 `runsOn` sites

```
$ grep -rn "runsOn\s*=" modules/ machines/ --include="*.nix" | wc -l
34
```

Cross-checked: every site is inside a `nori.lanRoutes.<X>` declaration. **Zero locations declare location-policy outside of route-registration today.** Coupling is real, not accidental.

Distribution across hosts:

```
runsOn = "workstation"   17 routes  (GPU + arr stack + ollama
                                     + jellyfin + open-webui + …)
runsOn = "aurora"        11 routes  (family-tier backends)
runsOn = "pi"             6 routes  (entry plane + observability +
                                     ntfy + tsdb + logs)
runsOn = "pavilion"       0 routes  (no exposed services — agent
                                     quarantine by design)
```

Pavilion's zero count is meaningful: hosts that legitimately run something locally (agent quarantine: hermes daemon) but don't expose it have NO `runsOn` declarations. Confirms the "lan-route is the cross-machine surface" framing.

## Counterfactual — would extracting `runsOn` help?

Three alternative shapes considered:

```
(α)  Keep coupled — lan-route stays the home (current state).
     Rationale: route-declared IS cross-machine-needed IS
     location-explicit. The three concerns degenerate at
     the host-local case (implicit), and they UNIFY at the
     cross-machine case (lan-route). No information at stake.

(β)  Extract location-policy as nori.runsOn.<X>.host —
     a separate module / option that lan-route reads.
     Cost: two declaration sites per service (one for the
     route, one for location); zero gain because every
     existing call site declares both together. A
     coupling-by-convention split that the call sites
     immediately re-couple.

(γ)  Defer until a second consumer of location-policy
     appears.
     Examples of what could be a second consumer:
       - A "follow the data" placement assertion module that
         checks fs-uses-X-data → runsOn-is-on-data-host
       - A "service must run on a host that has Y resource"
         capacity-check module
       - A multi-host runsOn (failover / loadbalance / sequential)
         scheduler that wants the host list separately from
         the proxy config
     None of these exist today. Rule of three.
```

**Recommend (α) with the (γ) trigger pre-named.** Keep coupled until 2+ independent location-policy consumers appear. At that point, extract as its own module and have lan-route consume it.

## The algebraic forward-extension (pre-named, not landing)

Today: `runsOn = "workstation"` — one host string.

Real future possibilities (operator-named):

```
runsOn = { hosts = [ ... ]; semantic = <tag>; }

  semantic = "failover"     sum type — first available
                            (Caddy `try_files`-like; OneSignal
                            failover)

  semantic = "loadbalance"  product type — all in parallel
                            (Caddy `lb_policy round_robin`;
                            requires stateless backends or
                            sticky-session config)

  semantic = "sequential"   sum type — operator-ordered
                            (try host[0]; on dead, host[1];
                            …) — same as failover semantically,
                            but with explicit precedence
```

Today's `runsOn = "workstation"` is sugar for `runsOn = { hosts = [ "workstation" ]; semantic = "failover"; }` — the degenerate case.

Concrete use cases worth pre-naming:

```
- Open-WebUI cold-failover from workstation → aurora when
  station is asleep (failover, sum)
- Future LLM gateway with parallel workers on workstation
  + aurora's GTX 950M (loadbalance, product)
- DNS forwarder: pi primary, workstation secondary
  (sequential, sum-with-priority) — partly modeled today
  via Blocky's own resolver list, not via runsOn
```

**Forward shape lands when a second host genuinely backs a route.** The string-or-attrset coercion stays cheap (`runsOn = "x"` → `[ "x" ]`).

## Folder-vs-file location for option modules

Operator's second framing: "whether to co-locate options in a singular file or a folder."

Today:
- `nori.lanRoutes` lives in `modules/infra/networking/default.nix` (single file, ~700 lines)
- `nori.backups` lives in `modules/services/backup/` (a folder — backup.nix + restic.nix + verify.nix + btrbk.nix)
- `nori.harden` lives in `modules/infra/capabilities/default.nix` (single file)
- `nori.fs` lives in `modules/infra/storage/default.nix` (single file)

The split-into-folder happens when ONE concept has multiple implementation surfaces (backup has: collect intents + restic dispatcher + verify check + btrbk replication). Lan-route has one (the schema + the generators). File-versus-folder isn't about complexity; it's about implementation-surface count.

If the structure-by-tier restructure (R3) happens, this question gets re-asked: location-policy (if extracted) would be one file at first, becoming a folder if/when assertion modules or capacity-check consumers land.

## Verdict for K7

```
COUPLING:               REAL — every runsOn site IS route-declared.
                        The three concerns degenerate to one at
                        host-local; unify at cross-machine.

EXTRACTION:             DEFER — no second consumer today; rule
                        of three not met.

FORWARD SHAPE:          PRE-NAMED — algebraic sum/product runsOn
                        landed in topology.md's tier-principle
                        section. Coerce string → list when first
                        multi-host route appears.

POSITION OF runsOn:     STAYS in lan-route. Document the WHY
                        (this analysis) inline as a brief comment.
```

## Action item (inline in this commit)

Add a one-paragraph note in the `runsOn` option description that points to this analysis and names the (γ) extraction trigger. Future drift catcher: if a second consumer of location-policy appears without the extraction discussion, the comment becomes the anchor.
