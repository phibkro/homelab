# Plan — scope backend access at the Tailscale ACL layer (not the host firewall)

Status: **proposed / optional** — depends on whether the operator wants to act
on the audit finding given the homelab's stated posture (see § Decision).

## Why this exists

The 2026-06-23 tonic security audit (M2) flagged that any tailnet peer can reach
service backends directly — e.g. `curl http://aurora-tailnet-ip:8222/`
(Vaultwarden) — bypassing pi's Caddy and its `audience`/Authelia gate.

A first attempt (ADR-0006, reverted in `1874efd`) tried to fix this with the
**NixOS host firewall** — appliance-scoped `allowedTCPPorts` / `extraInputRules`
on `tailscale0`. **It cannot work.** Tailscale installs a netfilter chain that
runs *before* the NixOS firewall and accepts the tailnet interface wholesale:

```
  iptables INPUT:   -A INPUT -j ts-input     ← Tailscale, runs FIRST
                    -A INPUT -j nixos-fw      ← NixOS firewall, runs SECOND
  ts-input:         ACCEPT all  -i tailscale0  0.0.0.0/0 → 0.0.0.0/0   (verified, 22 GB matched)
```

So per-port rules on `tailscale0` are inert for tailnet traffic. **The only
layer that can gate peer→backend access is the Tailscale ACL** (the tailnet
policy). The homelab already uses it for exactly this — `tag:agent` (pavilion)
is restricted to `workhorse:11434` (ollama) — so the mechanism is proven; it's
just not applied to the service backends.

## Current state

- Live ACL: admin UI (`login.tailscale.com/admin/acls/file`). Mostly
  default-allow within the tailnet (every member reaches every member:port),
  except the agent-tag restriction.
- `docs/runbooks/tailscale-acl.json`: recovery snapshot, currently `{}` — **must
  be populated from the live export before editing** (see tailscale-acl.md).

## The approach (if pursued)

Author `grants` in the ACL so devices reach only what they should:

```
  tag:appliance (pi)        → workhorse backend ports (so Caddy can reverse-proxy)
  user devices (operator)   → pi:443 (Caddy entry) + the DIRECT-CLIENT backend
                              ports only: jellyfin 8096, immich 2283, navidrome
                              4533, komga 8085, radicale 5232, calibre 8084,
                              miniflux 8087, qbittorrent 8083
  user devices              → NOT the Caddy-only backend ports (vaultwarden 8222,
                              *arr UIs, grafana 3000, open-webui) — those are
                              reachable only through pi:443/Caddy
  tag:agent (pavilion)      → workhorse:11434 (ollama)   [already present]
```

Net effect: browser users go through Caddy (which enforces `audience`/Authelia);
direct-client apps still reach their specific backend ports; the pure-web-UI
backends are no longer curl-able around Authelia.

### Steps

1. **Tag the hosts.** Add `tag:appliance` (pi), `tag:workhorse` (workstation,
   aurora) via `--advertise-tags` (the homelab's tailscale `extraUpFlags`
   pattern) + `tagOwners` in the ACL. `tag:agent` exists already.
2. **Populate the snapshot.** Export the current live ACL into
   `tailscale-acl.json` first (so there's a known-good base + a diff).
3. **Write the grants** above in the admin UI. Tailscale's grants test harness
   (`tests` block in the policy) can assert "user device → vaultwarden:8222 is
   denied, → jellyfin:8096 is allowed" — author those tests alongside.
4. **Re-export** the snapshot into `tailscale-acl.json` and commit.
5. Verify live: from a non-appliance peer, `curl aurora:8222` → refused,
   `curl workstation:8096` → reachable.

This is admin-UI-managed (no `terraform apply` equivalent), so it's a manual
edit + re-snapshot, not a `nix rebuild`.

## Decision — is it worth doing?

The homelab's stated posture is **"Tailnet IS the auth perimeter; Authelia only
for per-user identity"** (CLAUDE.md). Under that posture, direct tailnet access
to a backend is acceptable *because the tailnet is the trust boundary* — and
every flagged service has its **own native login** (Jellyfin, Immich,
Vaultwarden master password, Navidrome, etc.). "Bypasses Authelia" ≠
"unauthenticated".

So this is **defense-in-depth, not a hole-plug** — it narrows what a *compromised
or untrusted tailnet device* (a family member's phone, a guest device) can reach,
shrinking the blast radius from "every backend" to "the entry plane + the apps
that device legitimately uses". Worth doing if the threat model includes
not-fully-trusted tailnet members; skippable if the tailnet is strictly the
operator's own trusted devices.

## What was learned (don't repeat)

- **Tailscale owns the tailnet firewall.** Host-firewall port rules on
  `tailscale0` are inert — `ts-input` accepts the interface before `nixos-fw`.
  Access control for tailnet traffic lives in the ACL, full stop.
- Verify security changes against the **live packet path** (`iptables-save`,
  a real `curl` from a real peer), not just the generated config. The eval test
  was green while the live behavior was unchanged the whole time.
