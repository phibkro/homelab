---
name: gotcha-python-ca-trust
description: USE WHEN a Python service (httpx / requests / urllib3 / aiohttp) hits a `*.nori.lan` URL and fails with `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` — Python doesn't trust the system CA bundle, certifi ships its own. Set `SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt` in the unit's environment.
---

# Python doesn't trust the system CA — `certifi` ships its own

`security.pki.certificateFiles` adds your CA to `/etc/ssl/certs/ca-bundle.crt` — Go, curl, openssl, libcurl all pick it up. **Python doesn't.** httpx / requests / urllib3 default to certifi's bundled trust store, which doesn't include local CAs.

Symptom: `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate`.

Fix: set `SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"` (and optionally `REQUESTS_CA_BUNDLE` for older requests-based libs) in the service's environment.
