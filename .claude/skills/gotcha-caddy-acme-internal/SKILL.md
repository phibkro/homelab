---
name: gotcha-caddy-acme-internal
description: USE WHEN configuring Caddy to use its internal CA / setting `services.caddy.acmeCA` — that option expects an ACME directory URL not a literal "internal"; Caddy will try to DNS-resolve "internal" and fail. Use `services.caddy.globalConfig = "local_certs"` instead.
---

# Caddy: `acmeCA = "internal"` is wrong

Looks like the right knob, isn't. NixOS module's `services.caddy.acmeCA` takes an ACME directory URL — Caddy will literally try to `dial tcp: lookup internal` and fail.

The right way to switch every vhost to Caddy's internal CA:

```nix
services.caddy.globalConfig = "local_certs";
```
