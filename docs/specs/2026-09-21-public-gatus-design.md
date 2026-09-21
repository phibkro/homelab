---
summary: Publish a minimal public family-service status page from Pi using Gatus.
date: 2026-09-21
status: frozen; deployed
owner: operator
---

# Public Gatus status

## Goal

`status.home.phibkro.org` shows the current reachability of Jellyfin, Navidrome,
and Seerr. It remains useful when the workstation is unavailable and exposes no
operator topology, credentials, or mutation surface.

## User journey

1. Open `https://status.home.phibkro.org` without authentication.
2. See exactly Jellyfin, Navidrome, and Seerr.
3. See each service's current health and recent response-time history.
4. Use the same page on a phone.

Maintenance notices, incident mutation, long-term history, and a custom status
application are not part of this contract.

## Authority and derivation

Workload manifests remain the authority for route identity, audience,
reachability, and monitoring intent. The inventory compiler derives the public
Gatus endpoint projection from routes that grant `publicStatus` and rejects
ambiguous names or non-HTTPS probes. Ansible renders the deployed Gatus YAML from
that projection. No second service catalog is maintained.

Pi Caddy publishes the exact `status.home.phibkro.org` route. The existing Pi
DDNS reconciler derives its DNS-only A record from the same internet-route
projection as the family-service records.

## Runtime boundary

Gatus runs on Pi because the status page must not share the workstation failure
domain it observes. It uses:

- the pinned upstream Gatus image;
- in-memory status storage;
- a non-root user, read-only root filesystem, dropped capabilities, and
  `no-new-privileges`;
- a dedicated bridge network with a static `/30` allocation;
- explicit host mappings for only the three public probe names;
- a LAN-bound health/UI port consumed by Caddy.

The dedicated bridge can initiate HTTPS only to its Caddy gateway. Pi's firewall
rejects new forwarding from that subnet, and Caddy excludes that subnet from all
internal-only routes. The public API hides probe hostnames, URLs, ports,
condition details, and errors.

## Clean cutover

The former Cloudflare Worker, custom-domain route, D1 database, mutation token,
application source, migrations, tests, package lock, and deployment state are
removed. Gatus has no public mutation endpoint and needs no Cloudflare API token
of its own.

## Acceptance gates

- The Pi deployment converges and is idempotent.
- Public HTML returns HTTP 200 through Caddy.
- The public JSON contains exactly the three approved names and only the safe
  Gatus result fields.
- Fresh probes report success for all three services.
- The status container can reach the approved public routes through Caddy.
- The same container namespace cannot reach an internal-only route, an
  unrelated Pi service, or the public Internet directly.
- Desktop and phone-sized browser views render all three states.
- The former Worker and D1 database no longer exist.
- Repository checks pass.

Cellular-data reachability and router source-address preservation belong to
ADR-0006 external acceptance. Pi reboot persistence belongs to the appliance
acceptance contract.
