---
name: gotcha-authelia-template-filter
description: USE WHEN configuring Authelia OIDC clients whose `client_secret` uses `{{ secret "/run/secrets/..." }}` template syntax — Authelia parses the literal template string and rejects every handshake with hash mismatch unless `X_AUTHELIA_CONFIG_FILTERS=template` is set on the unit. Legacy `_FILE` / `expand-env` paths don't work for list-typed sections.
---

# Authelia OIDC clients require `X_AUTHELIA_CONFIG_FILTERS=template`

OIDC client `client_secret` values use `{{ secret "/run/secrets/oidc-<n>-client-secret-hash" }}` template syntax (see `modules/infra/networking/default.nix` + `modules/infra/access/authelia.nix`). The substitution only happens when Authelia is invoked with the template config-filter enabled:

```nix
systemd.services.authelia-main.environment.X_AUTHELIA_CONFIG_FILTERS = "template";
```

Without it, Authelia parses the literal `{{ secret "..." }}` string as the client_secret and rejects every OIDC handshake with a hash mismatch. The legacy `_FILE` / `expand-env` substitution paths are explicitly **not** supported for list-typed config sections (which OIDC clients are); template filter is the only working path. `expand-env` is being removed in 4.40.
