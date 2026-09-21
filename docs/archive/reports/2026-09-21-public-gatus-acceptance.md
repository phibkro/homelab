# Public Gatus production acceptance — September 21, 2026

All times are UTC.

## Scope

This acceptance replaced the custom Cloudflare Worker status application with a
public-safe Gatus instance on Pi. It covered the source cutover, Cloudflare
resource retirement, Pi deployment, public output, live probe results, and the
status container's network boundary. It did not change the home router.

The accepted contract is
[`docs/specs/2026-09-21-public-gatus-design.md`](../../specs/2026-09-21-public-gatus-design.md).

## Cutover

The retired `HomelabPublicStatus` Worker, its custom domain, and its D1 database
were deleted. The status mutation token was removed from SecretSpec and the
encrypted operator secret. The `products/status` source, migrations, tests,
package lock, and local Alchemy state were removed.

Pi DDNS reconciled `status.home.phibkro.org` as a DNS-only A record. Pi Caddy now
serves the exact hostname and reverse-proxies the LAN-bound Gatus listener.

Two intermediate deployments stopped before Caddy convergence because a Podman
network marked `internal` cannot carry the published-port traffic this design
needs. The final design uses a dedicated routable bridge and enforces the egress
boundary in nftables. No intermediate failure was treated as acceptance.

## Observations

| Time | Observation |
| --- | --- |
| 16:08 | The final Gatus container loaded three endpoints and began one-minute probes. |
| 16:15 | The public API reported fresh successful HTTP 200 results for Jellyfin, Navidrome, and Seerr. |
| 16:17 | Public HTML returned HTTP 200 with `via: 1.1 Caddy`. |
| 16:17 | A recursive JSON-field check passed: the response contained exactly the three approved service names and only safe status/result fields. |
| 16:18 | Desktop and 390-pixel browser views rendered all three services as healthy. |

The deployed container is non-root (`65532:65532`), has a read-only root
filesystem, drops the default capability set, and enables `no-new-privileges`.
Its dedicated `gatus-public` bridge is `10.89.0.0/30`; Gatus uses `10.89.0.2` and
Caddy listens on gateway `10.89.0.1:443` as well as the LAN address.

Network-namespace probes established the intended boundary:

- `media.home.phibkro.org` through the Caddy gateway followed its redirect and
  returned HTTP 200;
- the internal-only `pihole.home.phibkro.org` host returned Caddy's HTTP 404;
- direct Internet traffic to `1.1.1.1:80` timed out;
- direct access to Pi's unrelated `192.168.1.225:8081` listener timed out.

The public API omitted endpoint URLs, resolved addresses, ports, probe
conditions, and errors. Its latest results exposed only service name/group/key,
HTTP status, duration, success, and timestamp.

## Result

The public Gatus cutover passed its production gates. Current health is derived
from the route inventory, rendered by Ansible, probed from Pi, and served by
Caddy. The custom Worker stack and its mutation surface are gone.

This evidence does not prove cellular-data reachability, router source-address
preservation, or persistence across a physical Pi reboot. Those gates remain in
ADR-0006 and the Pi appliance acceptance work. Gatus uses memory storage by
design, so its short response history resets when the container restarts.
