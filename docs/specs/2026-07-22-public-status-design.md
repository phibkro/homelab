---
date: 2026-07-22
status: accepted for implementation; production deployment remains operator-gated
owner: operator
implementation_branch: feat/public-status
summary: Publish a failure-independent family service status page at the Cloudflare edge from an explicit, minimal projection of the homelab route inventory.
---

# Design — public status and maintenance communication

## Decision

Build `status.home.phibkro.org` as an independently deployed Cloudflare Worker
with a D1 database. The Worker owns its small HTML UI, read-only public API,
scheduled external probes, incident history, and maintenance notices. Alchemy
v2 owns the Worker, D1 binding, cron trigger, and exact custom domain.

Keep Gatus internal. It remains the detailed operator diagnostic surface and
must never be proxied or copied wholesale to the public page.

The status product lives under `products/status/`: it has a distinct security
boundary, persistence lifecycle, test surface, release cadence, and failure
domain from the NixOS machines it observes.

## Goals

- Remain available while Pi, a workhorse, the residential WAN, or the entire
  homelab is unavailable.
- Tell family members whether their intentionally published services are
  operational, degraded, under maintenance, or unavailable.
- Derive component identity and canonical URLs from `nori.lanRoutes` through
  `noriInventory.status`; never maintain a second component list in TypeScript.
- Support planned maintenance and append-only incident updates without giving
  the edge product authority over homelab services.
- Supply the public component vocabulary later consumed by the family
  onboarding portal.

## Non-goals

- Publicly exposing a service, changing Caddy, DNS, router, or Tailscale policy.
- Publishing Gatus diagnostics, backend topology, or probe response bodies.
- Building the authenticated family portal or generated walkthroughs here.
- Automatically mutating status around every rebuild before the initial public
  surface and mutation boundary have been accepted.

## Boundary and data flow

```text
workload manifest endpoint.publicStatus
             │
             ▼
pure inventory compiler ──▶ status-json ──▶ checked generated components.json
                                                    │
                                                    ▼
Cloudflare Worker custom domain ◀──── scheduled public HTTPS probes
             │
             ├── GET /              public HTML
             ├── GET /api/status    public normalized JSON
             └── operator mutation API (phase 2, scoped bearer secret)
                          │
                          ▼
                         D1
```

`publicStatus = true` is an explicit disclosure grant. It is never inferred
from `audience`, `monitor`, dashboard membership, tags, or directory names. The
inventory compiler requires every published component to be monitored and
non-operator. Only routes that have passed external acceptance may receive the
grant.

The public status projection contains exactly:

```json
{
  "services": {
    "media": {
      "title": "Jellyfin",
      "description": "Movies, shows, music — server-rendered",
      "url": "https://media.home.phibkro.org"
    }
  }
}
```

It excludes ports, host placement, tailnet/LAN addresses, authentication
configuration, visibility policy, internal monitor paths and conditions,
response bodies, and secret-shaped values. The generated edge input is checked
for byte-for-byte freshness.

## Runtime model

Each component has one normalized state:

- `operational`
- `degraded`
- `maintenance`
- `outage`
- `unknown` before the first successful probe

The scheduled handler probes the canonical public HTTPS URL without
credentials, follows redirects, validates TLS, applies a short timeout, and
stores only status class, latency, normalized state, and timestamp. It never
stores response bodies or headers. A login page or expected authentication
redirect counts as reachable.

The initial release is read-only and probe-driven. The second phase adds:

- incidents with affected component IDs and append-only updates;
- maintenance windows with UTC start and expected end;
- a separately scoped mutation bearer secret;
- `maintenance-start`, `maintenance-finish`, and `push-maintained` operator
  commands that fail safely and leave notices open after interrupted rebuilds.

## Edge ownership

Alchemy v2 is selected because its current Cloudflare provider supports a
typed Worker environment, native D1 bindings, cron subscriptions, and Worker
custom domains in one stack. The custom domain creates the exact DNS record and
certificate at Cloudflare; no wildcard status route is created.

Production deployment is intentionally not part of ordinary `nix flake check`.
The repository checks build and test the artifact without Cloudflare
credentials. A reviewed operator action runs `alchemy plan`, inspects resource
adoption/replacement, and only then deploys the `prod` stage. Destructive
Alchemy operations remain separately confirmed.

## Security and privacy invariants

- Public handlers are GET/HEAD only in phase 1; all other methods fail closed.
- Unknown paths return 404 and do not fall through to another origin.
- HTML escapes every inventory- or database-derived string.
- JSON responses expose a versioned allowlisted schema.
- Security headers deny framing, MIME sniffing, referrer leakage, and ambient
  browser capabilities; scripts and styles are self-contained.
- Probe failures are normalized; public output contains no exception, stack,
  upstream response body, internal address, or Cloudflare diagnostic payload.
- D1 and the Worker can observe public service availability but cannot mutate
  the homelab.
- The future mutation credential is distinct from Cloudflare deployment tokens
  and homelab service credentials.

## Delivery gates

1. **Contract:** explicit publication flag, minimal `status-json`, negative eval
   tests, generated-input freshness check.
2. **Read-only vertical slice:** Worker UI/API, D1 state, scheduled probes,
   Alchemy resources, unit tests and local build.
3. **Production acceptance:** operator-reviewed plan, deploy, DNS/TLS/API/UI
   checks, then observe a controlled backend outage.
4. **Maintenance workflow:** authenticated mutations and rebuild wrapper with
   interruption-safe semantics.
5. **Portal follow-up:** reuse component IDs and presentation data for family
   registration and access guidance; do not couple portal authentication into
   the status Worker.

## Acceptance criteria

- Only `media`, `requests`, and `audio` appear in the first public manifest.
- Disabling or omitting `publicStatus` removes a component from the next build.
- A public-status grant on an operator or unmonitored route fails evaluation.
- A homelab `lanRoute` cannot claim the edge-owned
  `status.home.phibkro.org` hostname; the inventory compiler fails evaluation.
- Public HTML and JSON contain none of the forbidden topology/security fields.
- The Worker remains usable when all homelab hosts are offline.
- Unknown routes and mutation attempts without the phase-2 credential fail
  closed.
- No Cloudflare resource is created or changed before the push and deployment
  gates are explicitly approved.

## Rollback

Before deployment, revert the feature commit. After deployment, roll the Worker
back to its previous Cloudflare version; D1 remains additive and can be retained
for history. Removing the custom domain is a separate reviewed action. A status
failure never requires changing homelab service routing.

## Implementation references

- [Alchemy v2 Workers](https://v2.alchemy.run/cloudflare/compute/workers/)
- [Alchemy v2 Cloudflare DNS records](https://v2.alchemy.run/providers/cloudflare/dns/record/)
- [Cloudflare Worker custom domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
- [Cloudflare D1](https://developers.cloudflare.com/d1/)
