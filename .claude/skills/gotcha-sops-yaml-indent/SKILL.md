---
name: gotcha-sops-yaml-indent
description: USE WHEN editing multi-line block-string values in sops yaml (`key: |` form) — indent is significant; use 2 spaces, not tabs. Wrong indent decrypts to empty string. Verify with `sops -d secrets/secrets.yaml | grep <key>` before committing.
---

# sops block-string indentation matters

When using `|` for multi-line YAML values, the indent depth is significant. Tabs don't work — use 2 spaces:

```yaml
authelia-oidc-issuer-private-key: |
  -----BEGIN PRIVATE KEY-----
  MIIE...
  -----END PRIVATE KEY-----
```

If indent is wrong (or the value lands on the same line as the key), sops decrypts to an empty string. `sops -d secrets/secrets.yaml | grep <key>` is the fastest way to verify a value is non-empty.
