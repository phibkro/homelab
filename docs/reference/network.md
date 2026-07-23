---
summary: Cross-module network concerns — Authelia OIDC overview, Tailscale roles, SPOF mitigation, and the SSH/Samba/snapshot access summary that cuts across networking + access + storage modules. Single-module narrative (zones, DNS architecture, Caddy + TLS, lanRoutes overview, naming convention, audience trust model) lives co-located with the code at `modules/infra/networking/default.nix` and is surfaced in `docs/generated/lan-route.md`.
---

# Network — cross-module synthesis

The single-module narrative (zones, DNS architecture, `nori.lanRoutes`
schema, Caddy + TLS rationale, naming convention, audience trust model)
lives in [`docs/generated/lan-route.md`](../generated/lan-route.md),
extracted from the file-level doc-comment at
`modules/infra/networking/default.nix`. This file keeps the cross-module
content that doesn't fit one extraction site.

## Authelia OIDC (overview)

Authelia provides OIDC for services that opt in via
`nori.lanRoutes.<X>.oidc`. The networking concern generates the sops-
templated secrets; the access concern (`modules/infra/access/authelia/runtime.nix`)
consumes them to populate Authelia's client list. Per-service setup
is one declaration block; no edits scattered across two modules.

Hash material lives **only in sops** — Authelia's `template` config-
filter reads the PBKDF2 hash from `/run/secrets/...` at startup. Zero
hash material in committed Nix; the `forbidden-patterns` flake check
fails if a `$pbkdf2-` string lands.

Bootstrap a new OIDC client via `/add-oidc-client` skill. The skill
walks the secret generation + sops paste + route-block declaration +
systemd wiring. Bootstrap script: `just generate-oidc-key <name>`.

## Tailscale

| Host | Tailscale role | Advertises |
|---|---|---|
| pi | router | `--advertise-routes=192.168.1.0/24` (subnet) + `--advertise-exit-node` (opt-in) |
| workstation | regular node | — |
| pavilion / aurora | regular node | — |
| macbook | regular node | — |

Subnet route + exit node require one-time approval in the Tailscale
admin console. MagicDNS gives every host a stable `<host>.saola-matrix.ts.net`
name.

## Internet entry plane

WAN TCP 443 may be forwarded to Caddy on pi. This does not publish the
whole wildcard vhost: each `nori.lanRoutes` entry defaults to
`reachability = "internal"`, which combines its host matcher with a
private/LAN or Tailscale-source matcher. Only `reachability = "internet"`
omits that address gate. Unknown hostnames hit a final 404 handler.

The current internet allowlist is `media` (Jellyfin), `requests` (Seerr),
and `audio` (Navidrome). Each uses its application's native per-user
accounts because TV, mobile, PWA, and OpenSubsonic clients cannot reliably
complete a proxy-cookie login flow. Operator routes are forbidden from
selecting internet reachability by a module assertion.

Pi's `cloudflare-ddns` service derives its IPv4-only domain list from that
same allowlist and reconciles the three exact records every five minutes.
It sets `PROXIED=false`, never publishes a wildcard or AAAA record, and
uses an anchored record-comment selector so it mutates only records it owns.
On a graceful configuration restart, the old unit removes its owned records
before the new allowlist is created; this makes an internet-to-internal route
transition fail closed. Its zone-scoped API token is rendered from sops;
desired state remains entirely in Nix.

The remaining external step is to forward WAN TCP 443 to pi at
`192.168.1.225:443`. Do not forward port 80; certificate issuance already
uses DNS-01. After changing the router, verify from a cellular connection
that the three family names load, an internal-only known name returns 404,
and a random name returns 404. If the router source-NATs inbound
connections, the internal matcher cannot distinguish them from LAN
clients; replace or reconfigure the router rather than carrying sustained
Jellyfin/Navidrome media through a Cloudflare self-serve proxy.

See ADR-0006 for the decision and fallback constraints.

**SSH ACL: `action: accept`** (since 2026-06-07). Eliminates the periodic
browser reauth dance for cross-host SSH automation. Tailnet membership
IS the gate. Edited in admin UI JSON, not in this repo. See
[[just-remote-tailnet-hostnames]].

**SPOF mitigation for pi:** heartbeat to healthchecks.io every 60s via
`modules/infra/observability/heartbeat/`. Pi dies → hc.io alerts
off-host. Pre-fix, pi outage would have taken its own alert delivery
(ntfy server) with it.

## Access summary

| Path | SSH (user) | SSH (root) | Samba | Snapshot |
|---|---|---|---|---|
| `/home/nori` | Yes | Yes | No | Hourly |
| `/srv/share` | Yes | Yes | Yes (auth) | Daily |
| `/mnt/media/streaming` | Yes | Yes | Yes (auth, RW) | Weekly |
| `/mnt/media/photos` | Yes | Yes | No | Daily |
| `/mnt/media/home-videos` | Yes | Yes | No | Weekly |
| `/mnt/media/projects` | Yes | Yes | Yes (auth) | Weekly |
| `/var/lib/<service>` | No | Yes | No | Daily |
| `/etc`, `/nix`, `/root` | No | Yes | No | Per rebuild (`@`) |

OS has one user (Philip). Family members get per-service accounts in
Jellyfin, Seerr, Navidrome, Immich, Open WebUI, and Vaultwarden. Tailscale
invitations are needed only for internal services; the three ADR-0006
family-media routes work through their native accounts without tailnet
enrollment. Cross-cuts the networking concern (Samba is a service module,
not a networking adapter); kept here because the access answer to "what
can each path serve over which protocol" is the question the operator
actually asks.
