# Public status and maintenance communication

- Status: Superseded by `docs/specs/2026-07-22-public-status-design.md`
- Date: 2026-07-19
- Scope: family-facing internet services only

Retained as the banked design precursor. The later spec binds implementation to
the inventory-backed public-status projection and is the active contract.

## Problem

Family members need one unauthenticated page that answers whether Jellyfin,
Seerr, and Navidrome are available and whether downtime is planned. Rebuilds
of workstation, aurora, or pi can interrupt those services even when the
configuration change is healthy.

The existing Gatus page is not a safe public surface. Pi's evaluated instance
contains internal service names, tailnet addresses, operator-only endpoints,
and raw diagnostic results. It also shares the pi/Caddy/residential-WAN failure
domain: during an entry-plane outage, the status page would disappear alongside
the services it is meant to explain.

Gatus 5.36 supports announcements, archived incident communication, global and
per-endpoint maintenance windows, and SQLite history. Those capabilities remain
useful for the internal operator page, but do not solve failure independence or
inventory disclosure.

## Proposed architecture

Host `status.home.phibkro.org` at the Cloudflare edge, independently of the
homelab entry plane:

- a small public Pages/Worker frontend;
- a scheduled Worker that probes the canonical public HTTPS origins;
- D1 storage for component state, incidents, maintenance notices, and history;
- Cloudflare DNS and Worker resources managed declaratively with Alchemy v2;
- public read-only status APIs; authenticated mutation APIs protected by a
  scoped operator credential held in sops.

Do not expose or proxy the existing Gatus UI. Keep it internal for detailed
operator diagnosis, potentially renaming its route from `status` to `monitor`
when the external page takes ownership of the canonical `status` name.

## Single source of components

Generate a deployment manifest from `nori.lanRoutes` rather than maintaining a
second service list. Include only routes where `reachability = "internet"` and
emit only public-safe fields:

```json
[
  {"id":"media","label":"Jellyfin","url":"https://media.home.phibkro.org"},
  {"id":"requests","label":"Requests","url":"https://requests.home.phibkro.org"},
  {"id":"audio","label":"Music","url":"https://audio.home.phibkro.org"}
]
```

Never publish backend addresses, `runsOn`, tailnet IPs, raw response bodies,
condition expressions, stack traces, or operator-only route names.

## Public state model

Each component has one of four public states:

- `operational`
- `degraded`
- `maintenance`
- `outage`

Incidents and maintenance notices carry an affected-component list, UTC start
and expected-end timestamps, a short non-technical message, and an append-only
update history. Resolved items remain visible as history.

External probes should follow the same paths a family client uses and validate
TLS. A successful application login-page response or expected redirect counts
as healthy; probes must not authenticate or contain family credentials.

## Rebuild workflow

Add explicit operator commands rather than hiding status mutations inside every
ordinary rebuild:

```text
just maintenance-start <host> <duration> <message>
just push-maintained <host> <duration> <message>
just maintenance-finish <incident-id>
```

The host-to-component projection is derived from the same route registry:

- workstation maintenance affects Jellyfin and Requests;
- aurora maintenance affects Music;
- pi maintenance affects every public component because pi owns DNS, TLS, and
  reverse proxying.

`push-maintained` must publish the notice before activation. Failure to publish
blocks a planned disruptive rebuild unless the operator explicitly overrides
it. After activation it waits for external probes to recover before marking the
notice resolved. On interruption or failed verification, leave the notice open;
never announce “operational” merely because `nixos-rebuild` exited successfully.

Routine rebuilds proven not to restart or interrupt public components may keep
using `just push`. The maintenance wrapper is for user-visible risk, not noise.

## Security and privacy

- Public API is read-only and rate-limited.
- Mutation credentials are separate from the broad Cloudflare account token and
  scoped only to status records.
- No arbitrary Markdown/HTML without sanitization.
- Component IDs and labels are an explicit public projection.
- Probe failures are normalized to non-sensitive messages.
- Status infrastructure cannot mutate homelab services.

## Delivery phases

1. Generate and test the public component manifest from `lanRoutes`.
2. Create the Worker/Pages/D1 resources and exact public DNS record with
   Alchemy v2.
3. Implement external probes and the read-only status page.
4. Add authenticated incident/maintenance mutations.
5. Add `maintenance-*` and `push-maintained` recipes with failure-safe cleanup.
6. Rename the internal Gatus route and update Glance after the external page is
   accepted.

## Acceptance criteria

- The page remains available when pi, workstation, aurora, or the residential
  WAN is unavailable.
- Only internet-allowlisted components appear.
- A planned aurora rebuild shows Music in maintenance before interruption and
  resolves only after an external probe succeeds.
- A failed workstation rebuild leaves Jellyfin and Requests in maintenance or
  outage with an open incident.
- Internal route names, IP addresses, and diagnostic payloads never appear in
  public HTML or API responses.
- Unknown public status hostnames and mutation requests without authorization
  fail closed.

## Rejected shortcut

Publishing a second sanitized Gatus instance on pi is useful as a prototype but
not the canonical status service: it disappears during pi, power, WAN, router,
DNS, or Caddy failures and therefore cannot explain the most important outage
class.
