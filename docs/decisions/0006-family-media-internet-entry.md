# ADR-0006: Exact family-media internet entry through pi

- Status: Accepted
- Date: 2026-07-18
- Reverses: the “no public internet hosting from the homelab” rationale

## Context

Requiring every family phone, PC, television, and Chromecast to join the
tailnet adds device enrollment and support work to ordinary media use.
Jellyfin, Seerr, and Navidrome already have native per-user account models;
their family-facing clients work best when they can reach a normal HTTPS
origin directly. In particular, television clients and OpenSubsonic music
clients cannot reliably complete a browser-cookie forward-auth flow.

The pi already owns the HTTP entry plane and a Let's Encrypt wildcard
certificate. The risk is that every homelab route shares that wildcard
vhost: forwarding WAN 443 without a second boundary would let an external
caller reach an operator UI by guessing its hostname or supplying its Host
header, even if public DNS did not advertise the name.

## Decision

Permit WAN TCP 443 to reach Caddy on pi, but publish and accept only an
explicit family-media allowlist:

| Name | Service | Identity boundary |
|---|---|---|
| `media.home.phibkro.org` | Jellyfin | Native Jellyfin users |
| `requests.home.phibkro.org` | Seerr | Imported Jellyfin users |
| `audio.home.phibkro.org` | Navidrome | Native Navidrome users |

`nori.lanRoutes.<name>.reachability` is independent from `audience`:

- `internal` is the default and adds a Caddy client-IP matcher for private
  ranges plus Tailscale's `100.64.0.0/10` range.
- `internet` accepts any source address for that exact host. An assertion
  forbids operator-audience routes from selecting it.
- A final Caddy handler returns 404 for unknown or network-ineligible hosts.

Public DNS must use three exact DNS-only records, not a wildcard. WAN port
80 remains closed because Caddy obtains certificates using DNS-01. Pi's
`cloudflare-ddns` service derives those records from the same
`reachability = "internet"` route inventory, updates their IPv4 address
every five minutes, and explicitly disables Cloudflare proxying and IPv6.
Unauthenticated Navidrome sharing is disabled; Seerr membership is an
explicit Jellyfin-user import with request-only permissions and operator
approval policy.

## Deployment and acceptance

1. Deploy the pi, workstation, and aurora configurations. Pi's DDNS unit
   creates or updates exact A records for `media`, `requests`, and `audio`.
2. Confirm those records are DNS-only and resolve to the residential WAN
   address. Confirm no wildcard or AAAA record exists.
3. Forward WAN TCP 443 to `192.168.1.225:443` on pi. Do not forward TCP 80.
4. From cellular data with Tailscale disabled, verify all three public
   names reach their login page.
5. From the same connection, request a known internal-only hostname and a
   random hostname. Both must return 404, not an application or redirect.
6. Verify a non-admin Jellyfin user can play media, sign into Seerr and
   submit a request without management permission, and sign into a
   Navidrome/OpenSubsonic client without seeing another user's state.

The source-address tests are load-bearing. If the router source-NATs
forwarded traffic to a private address, Caddy will misclassify internet
callers as LAN clients. Do not accept that state.

## Consequences

- Family media no longer requires Tailscale enrollment.
- Operator and other internal services remain available through the same
  Caddy listener without becoming internet-reachable.
- Native application authentication becomes internet-facing and must use
  unique passwords, rate limiting where supported, prompt updates, and
  account disablement when access is revoked.
- Workstation sleep still affects Jellyfin and Seerr availability;
  internet reachability does not create high availability.
- The residential WAN address and router forwarding become operational
  dependencies. Dynamic DNS must keep the three exact records current if
  the ISP changes the address.
- The planned family portal/documentation system is intentionally deferred
  until this boundary is deployed and externally verified.

## Alternatives considered

### Enroll every family device in Tailscale

This retains the strongest network boundary but pushes enrollment and
ongoing device support onto non-technical users, and some television or
Chromecast environments remain awkward. Tailscale remains the operator and
internal-service access path.

### Tailscale Funnel

Funnel keeps router configuration closed but adds a relayed, product-limited
path to sustained media streaming. It remains useful for small HTTP services,
not the preferred Jellyfin transport.

### Cloudflare Tunnel or proxied DNS

Rejected for sustained Jellyfin and Navidrome delivery. Cloudflare's
self-serve application terms current at this decision require an eligible
paid service for video and other large-file delivery through its CDN and
permit limiting disproportionate audio or large-file traffic. Tunnel can
publish ordinary HTTP applications, but it does not turn that media policy
into a suitable transport. A future small non-media service may still use
an exact-host tunnel with a final `http_status:404` catch-all.

### Alchemy v1/v2 for Cloudflare resources

Technically capable: v1 exposes DNS Records and Tunnel resources; v2 has
first-class `Cloudflare.DNS.Record`, `Cloudflare.Tunnel.Tunnel`, and
`Cloudflare.Tunnel.Configuration` resources. It is not selected here.
Alchemy reconciles when its TypeScript deployment runs, while residential
DDNS needs a small continuously running updater. Adding a second IaC state
engine for three records would also weaken the route registry's role as the
single source of truth. Revisit Alchemy if this repository begins managing
a broader Cloudflare edge stack declaratively.

Sources consulted 2026-07-18: [Cloudflare application service-specific
terms](https://www.cloudflare.com/service-specific-terms-application-services/),
[Cloudflare Tunnel routing](https://developers.cloudflare.com/tunnel/routing/),
[Alchemy v1 Tunnel](https://alchemy.run/cloudflare/networking/tunnel/),
[Alchemy v2 DNS Record](https://v2.alchemy.run/providers/cloudflare/dns/record/),
and [Alchemy v2 Tunnel Configuration](https://v2.alchemy.run/providers/cloudflare/tunnel/configuration/).

### Publish the wildcard and rely only on missing DNS records

Rejected. DNS is discovery, not access control: callers can send an
arbitrary Host header to the public IP. Route-level address matchers and the
catch-all are required even with exact public records.
