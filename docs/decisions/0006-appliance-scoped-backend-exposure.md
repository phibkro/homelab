# ADR-0006: Appliance-scoped backend exposure (refines ADR-0003's reach mechanism)

- Status: Accepted
- Date: 2026-06-23
- Refines: ADR-0003 — the *pi-central entry plane* decision stands; the *how
  cross-host backends become reachable by pi's Caddy* mechanism is replaced.
- Source: security audit of tonic surfaced the gap as a systemic `nori.lanRoutes`
  property (tonic#12 was filed against a stale topology; corrected here).

## Context

ADR-0003 put Caddy on pi (the appliance) and moved family/operator backends to
aurora/workstation. To let pi's Caddy reverse-proxy a cross-host backend over
the tailnet, the 2026-06-12 cutover marked **every** cross-host route
`exposeOnTailnet = true`.

But `exposeOnTailnet` opens the backend port to **all** tailnet peers, not just
pi:

```
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ <port> ]
  # ↑ unscoped: every tailnet device can reach the backend directly,
  #   bypassing Caddy and the route's `audience` gate.
```

So one flag served two purposes — *be reachable by the entry-plane Caddy* and
*be reachable by every peer* — and the second was unintended. Impact ladder:

```
  family / forwardAuth (10 routes)   direct hit BYPASSES Authelia/OIDC  ⚠ auth bypass
  operator             (11 routes)   needless surface (tailnet=auth anyway)
  public               (4 routes)    harmless (no auth to bypass)
```

A tailnet device (a family member's phone, a compromised host, anything the
Tailscale ACL admits) could `curl https://aurora-tailnet-ip:8222/` and reach
Vaultwarden's backend without ever passing the OIDC gate Caddy fronts.

`network reachability ≠ origin/identity trust` — the same category error the
tonic CSRF ADR named, one layer down: tailnet membership was being treated as
sufficient for endpoints whose own design says it isn't.

## Decision

Decompose the two concerns:

1. **Caddy-reach is automatic and appliance-scoped.** For every cross-host
   route, the lan-route generator opens the backend port on `tailscale0`
   **only to the appliance host(s)** (`role == "appliance"` in `nori.hosts` —
   the single source of truth for "runs the entry plane"), via an nftables
   `extraInputRules` source-IP match. No opt-in: it's structurally required for
   the route to function, so it's not a flag anyone can forget or over-broaden.

2. **`exposeOnTailnet` reverts to its honest meaning** — open the port to
   *every* tailnet peer, bypassing Caddy. Rare, explicit, for genuine
   legacy-client / programmatic direct access. **Forbidden on `family` audience
   or any `forwardAuth` route** by a module assertion: direct access there
   defeats the per-user auth. `operator`/`public` may opt in.

3. **Scoped direct access to a specific peer** (e.g. an agent host reaching
   ollama's API) is a service-local `firewall.extraInputRules` admitting that
   peer by IP — see `modules/services/ollama.nix` (pavilion → `:11434`). Mirrors
   the Tailscale ACL (`tag:agent → workhorse:11434`) at the host firewall.

```
  request path AFTER this ADR
  ───────────────────────────
  browser ─https─▶ pi Caddy ─(tailnet, appliance-scoped hole)─▶ aurora:8222 backend
                     │ enforces audience (OIDC for family)
  other peer ─curl─▶ aurora:8222   ✗ REJECTED (firewall admits only pi)
  pavilion  ─api──▶ workstation:11434  ✓ (ollama service-local agent rule)
```

## Consequences

- **+** The auth bypass is closed by construction: a cross-host backend admits
  only the appliance, so a route's `audience` can't be skipped by hitting the
  port directly. The assertion makes any future family-route `exposeOnTailnet`
  a build error.
- **+** One generator change fixes all cross-host routes; 25 service modules
  shed a now-redundant (and over-broad) flag. SoT preserved — appliance IP
  derives from the role registry, no hardcoded `100.x`.
- **+** Reduced attack surface even for operator routes (no longer all-peer).
- **−** A genuine all-peer direct-access need on a `family` route would now be a
  build error — correct by design; revisit only if a real case appears.
- **−** Relies on `role == "appliance"` meaning "runs Caddy". True today (pi);
  documented in the `nori.hosts.role` enum. If an appliance ever runs *without*
  Caddy, that coupling needs an explicit `runsEntryPlane` marker instead.

The real-journey check (curl from pi succeeds; curl from a non-appliance peer
fails) is operator-side — it needs the live tailnet — and lives in the
`test-routes` lever + the deploy gate. The eval test
(`tests/eval/route-invariants.nix`) covers the generated-config invariant:
cross-host reach is appliance-scoped and the all-peer port list stays empty.
