---
name: gotcha-blocky-stale-negative-on-new-lan-route
description: USE WHEN a freshly-added `nori.lanRoutes.<name>` doesn't resolve from clients on the tailnet, even after rebuild — typically `Could not resolve host: <name>.${nori.domain}` or `NXDOMAIN`. Pi Blocky caches the negative result from before the record existed and survives a service restart triggered by a config-hash-stable rebuild. Fix: `sudo systemctl restart blocky.service` on pi.
---

# Pi Blocky caches NXDOMAIN across a new lan-route

## Symptom

You add `nori.lanRoutes.foo` and rebuild the homelab (pi + the runsOn host).
`https://foo.home.phibkro.org` is unreachable from clients. Direct probes:

```sh
dig +short @100.100.71.3 foo.home.phibkro.org   # pi Blocky → empty / NXDOMAIN ✗
dig +short @100.81.5.122 foo.home.phibkro.org   # workstation Blocky → 192.168.1.225 ✓
```

Tailscale's global-nameserver push points tailnet clients at pi Blocky, so the whole tailnet sees the stale negative.

## Cause

Post-ADR-0003, pi Blocky is **self-hosted authoritative** — it auto-generates the `*.${nori.domain}` customDNS map from `nori.lanRoutes` (every route name → pi's LAN IP, since pi is the Caddy host). A rebuild adds the new route name to the map. **But** if the rebuild doesn't change pi Blocky's *config hash* (common when only the service-side module changed, not the route declaration or any other blocky-relevant setting), systemd doesn't restart `blocky.service`, so the in-memory negative cache from before the record existed survives. Blocky's `caching.maxTime` is 30 min by default.

Workstation Blocky runs the same self-hosted role as a fallback secondary, but it goes through its own rebuild cycle and is hit much less often by tailnet clients.

## Fix

```sh
ssh nori@pi.saola-matrix.ts.net 'sudo systemctl restart blocky.service'
```

Then re-probe (you may also need `sudo nscd --invalidate=hosts` on local clients if they cached the negative).

## Prevention

`just rebuild-homelab` (rebuild pi + every other host in sequence) is the right primitive when adding a new lan-route. The `add-service` skill's lan-route step ends with the explicit Blocky-cache flush.

## Why not "fix Blocky to not cache negatives"

Negative caching is a real performance feature — disabling it would mean every typo gets a slow upstream round-trip. The cache is doing its job; the asymmetry is *new* lan-routes specifically, which is a known-rare event with a known one-line workaround. Live with the gotcha rather than removing the caching.
