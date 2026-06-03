---
name: gotcha-caddy-root-cert-install
description: USE WHEN Caddy logs `pki.ca.local | failed to install root certificate | failed to execute tee: exit status 1` — non-fatal, the systemd hardening blocks the install attempt; Caddy still serves certs from its own store. Ignore the noise.
---

# Caddy: "failed to install root certificate" is non-fatal

When Caddy generates its internal CA, it tries to install the root cert into `/etc/ssl/certs/...` via `tee`. The systemd-hardened service can't write there. You get a noisy error log like:

```
pki.ca.local | failed to install root certificate | error: failed to execute tee: exit status 1
```

Caddy continues serving certs anyway from its own store. Ignore the error. We install the root CA on devices manually + add it to the system trust store via `security.pki.certificateFiles`.
