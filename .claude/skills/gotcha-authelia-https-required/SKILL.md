---
name: gotcha-authelia-https-required
description: USE WHEN configuring `authelia_url` (in Authelia 4.39+) — must be HTTPS; HTTP rejected at config-validation as "does not have a secure scheme". Use Caddy reverse proxy with internal CA OR `tailscale serve --https`.
---

# Authelia 4.39 requires HTTPS for `authelia_url`

You can't set `authelia_url = "http://..."` in the cookies config — Authelia rejects it at config-validation time as "does not have a secure scheme". Need real HTTPS.

For tailnet-only access, two paths:

1. **`tailscale serve` with HTTPS termination** (auto-LE certs for tailnet hostname): one-time imperative `sudo tailscale serve --bg --https=PORT http://localhost:9091`. Persists in tailscaled state.
2. **Caddy reverse proxy** with internal CA (current setup): `https://auth.nori.lan` via Caddy.

Either works. We chose (2) for consistency with the rest of the *.nori.lan services.
