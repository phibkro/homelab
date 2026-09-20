---
summary: Cross-module network concerns: compiler-owned routes, Authelia OIDC, Tailscale roles, SPOF mitigation, and access paths across networking, identity, and storage.
---

# Network — cross-module synthesis

Workload manifests own endpoint declarations. `inventory/default.nix` validates
them, resolves host placement, and publishes `lib.noriInventory.routes`.
[`docs/generated/routes.md`](../generated/routes.md) is the generated active
route table. The Pi Ansible projection derives Caddy, Pi-hole, Gatus, and
Authelia configuration from the same compiler output.

## Authelia OIDC (overview)

Services declare OIDC clients under `endpoints.<name>.oidc` in their manifests.
The inventory compiler derives the Pi client registry. The Authelia Ansible
role resolves each declared hash input through the production SecretSpec
environment. Nix-managed workloads receive only their host-local raw client
secret. Generated inventory and committed configuration contain no production
client hashes.

## Tailscale

| Host | Tailscale role | Advertises |
|---|---|---|
| pi | router | `--advertise-routes=192.168.1.0/24` (subnet) + `--advertise-exit-node` (opt-in) |
| workstation | regular node | — |

Subnet route + exit node require one-time approval in the Tailscale
admin console. MagicDNS gives every host a stable `<host>.saola-matrix.ts.net`
name.

## Internet entry plane

WAN TCP 443 may be forwarded to Caddy on Pi. This does not publish the
whole wildcard vhost. Each manifest endpoint defaults to internal
reachability. The compiler makes that boundary explicit in every projected
route. Only `reachability = "internet"` removes the private-address gate.
Unknown hostnames receive a 404 response.

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
transition fail closed. Its zone-scoped API token comes from SecretSpec;
`services/cloudflare-ddns/ansible/` applies the desired state derived from the route inventory.

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
`services/heartbeat/ansible/`. Pi dies → hc.io alerts
off-host. Pre-fix, pi outage would have taken its own alert delivery
(ntfy server) with it.

## Access and storage

Workstation SSH, Samba exports, and snapshot policy are declared in
`infra/common/nixos/ssh.nix`, `services/samba/`, and
`infra/workstation/`. Consult the [storage reference](storage.md) and
[generated backup inventory](../generated/backups.md) for data protection.

Family members use per-service accounts. Tailscale invitations are needed
for internal services; internet-facing family-media routes use their native
accounts. Pi's declared backup transport uses an SFTP jail on workstation's
OneTouch; verify the deployed identity and isolation using the
[cutover runbook](../runbooks/onetouch-backup-cutover.md).
