---
name: gotcha-tailscale-funnel-port-conflict
description: USE WHEN adding `nori.funnelRoutes` or running `tailscale funnel`, see `bind: address already in use` on `100.x.y.z:443` — Caddy owns `0.0.0.0:443` for *.nori.lan, tailscaled can't get the tailnet 443. Use port 8443 (tailscale public edge maps internet :443 → local :8443 transparently).
---

# Tailscale Funnel must use port 8443 (not 443) when Caddy is running

Funnel allows binding 443/8443/10000 locally. On this homelab, **Caddy already owns `0.0.0.0:443`** for `*.nori.lan` reverse-proxy, so tailscaled can't get the tailnet-interface 443. Symptom in `journalctl -u tailscaled.service`:

```
localListener failed to listen on 100.81.5.122:443, backing off:
listen tcp4 100.81.5.122:443: bind: address already in use
```

Followed by TLS handshakes returning "internal error" (because the cert never loaded — the listener never came up).

Fix: use 8443 in `nori.funnelRoutes` (already encoded in `modules/effects/funnel-route.nix`). Tailscale's public-edge maps internet `:443` → local `:8443` transparently — visitors hit `https://<host>.<tailnet>.ts.net/<path>` (no port shown). Inside-tailnet direct access uses `:8443`.
