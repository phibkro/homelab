---
name: gotcha-blocky-stale-negative-on-new-lan-route
description: USE WHEN a freshly-added `nori.lanRoutes.<name>` doesn't resolve from clients on the tailnet, even after rebuild — typically `Could not resolve host: <name>.nori.lan` or `NXDOMAIN`. Pi Blocky caches the negative result from before the record existed and survives a service restart triggered by a config-hash-stable rebuild. Workstation Blocky knows the record; pi Blocky lies. Fix: `sudo systemctl restart blocky.service` on pi.
---

# Pi Blocky caches NXDOMAIN across a new lan-route

## Symptom

You add `nori.lanRoutes.foo` and rebuild the homelab (workstation + pi).
`https://foo.nori.lan` is unreachable from clients. Direct probes:

```sh
dig +short @192.168.1.181 foo.nori.lan   # workstation Blocky → 192.168.1.181 ✓
dig +short @100.100.71.3 foo.nori.lan    # pi Blocky → empty / NXDOMAIN ✗
```

Tailscale MagicDNS forwards `*.nori.lan` to pi Blocky (per the tailnet ACL), so the whole LAN sees the stale negative.

## Cause

`conditional.mapping.nori.lan: 192.168.1.181` in pi Blocky's config means "forward every `*.nori.lan` query to workstation Blocky." Workstation Blocky correctly answers `foo.nori.lan → 192.168.1.181` post-rebuild. **But** pi already cached the NXDOMAIN from before the record existed — Blocky's TTL on negative caches is `caching.maxTime` (default 30m) and **persists across systemd-managed restarts unless the unit's config hash changed**. A rebuild that touched, say, only the workstation-side service module doesn't change pi Blocky's config hash, so systemd doesn't restart blocky.service on pi, so the cache survives.

## Fix

```sh
ssh nori@pi.saola-matrix.ts.net 'sudo systemctl restart blocky.service'
```

Then re-probe (you may also need `sudo nscd --invalidate=hosts` on local clients if they cached the negative).

## Prevention

`just rebuild-homelab` (sequential workstation + pi rebuild) is the right primitive when adding a new lan-route. The `add-service` skill's lan-route step now ends with the explicit Blocky-cache flush.

## Why not "fix Blocky to not cache negatives"

Negative caching is a real performance feature — disabling it would mean every typo gets a slow upstream round-trip. The cache is doing its job; the asymmetry is *new* lan-routes specifically, which is a known-rare event with a known one-line workaround. Live with the gotcha rather than removing the caching.
