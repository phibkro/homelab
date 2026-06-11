---
name: add-oidc-client
description: USE WHEN bootstrapping a new Authelia OIDC client for a service that wants SSO via `auth.nori.lan` — generates raw+hash secrets, pastes into sops, declares the route's `oidc` block, wires the consuming systemd unit. Hash material lives ONLY in sops (Authelia's `template` filter reads at startup); the `forbidden-patterns` flake check fails the build on stray `$pbkdf2-` strings.
---

# Bootstrap a new Authelia OIDC client

OIDC clients are auto-generated from `nori.lanRoutes.<n>.oidc`. The abstraction owns the Authelia client entry, the sops secret(s), and the env-file template; the consuming service module owns its own systemd wiring (`EnvironmentFile`, `SupplementaryGroups`) and the non-secret OIDC env vars (provider URL, client_id, etc.).

**Hash material lives only in sops.** Authelia's `template` config-filter (`X_AUTHELIA_CONFIG_FILTERS=template`, set in `authelia.nix`) reads the PBKDF2 hash from `/run/secrets/oidc-<n>-client-secret-hash` at startup and substitutes it into the YAML config before parsing — zero hash material in committed Nix. Enforced by the `forbidden-patterns` flake check; a stray inline `$pbkdf2-` string fails `nix flake check`.

## Steps

### 1. Generate raw + hash

```sh
just generate-oidc-key <name>
```

Output is sensitive — lands in your terminal, not in any file or shell history. Two values to copy.

### 2. Paste both into sops

```sh
sops secrets/secrets.yaml
```

```yaml
oidc-<name>-client-secret: '<raw — opaque base64-ish blob>'
oidc-<name>-client-secret-hash: '$pbkdf2-sha512$310000$...'
```

Single-quote the hash so YAML doesn't interpret the `$` chars. Single-quote the raw too if it happens to contain YAML-special characters — usually safe, but harmless.

### 3. Declare the route's `oidc` block

In the service's module (`modules/services/<svc>.nix`) — the service module is the single source of truth for the route; co-locate everything about that service:

```nix
nori.lanRoutes.<name> = {
  port = N;
  monitor = { };
  oidc = {
    clientName  = "Display Name";
    redirectPath = "/path/the/service/uses";
    # Optional overrides (defaults shown):
    # scopes = [ "openid" "profile" "email" "groups" ];
    # authorizationPolicy = "one_factor";
    # secretEnvName = "OAUTH_CLIENT_SECRET";  # → SSO_CLIENT_SECRET for Vaultwarden, etc.
  };
};
```

Common `redirectPath` values:

| Service | Path |
|---|---|
| Open WebUI | `/oauth/oidc/callback` |
| PocketBase | `/api/oauth2-redirect` |
| Vaultwarden | `/identity/connect/oidc-signin` |

### 4. Wire the consuming systemd unit

In the same module:

```nix
systemd.services.<svc>.serviceConfig = {
  EnvironmentFile = config.sops.templates."oidc-<name>-env".path;
  SupplementaryGroups = [ "keys" ];   # DynamicUser needs this to read /run/secrets/rendered/*
};
```

Plus non-secret OIDC env vars in `services.<svc>.environment`:

```nix
OPENID_PROVIDER_URL = "https://auth.nori.lan/.well-known/openid-configuration";
OAUTH_CLIENT_ID     = "<name>";
OAUTH_PROVIDER_NAME = "Authelia";
ENABLE_OAUTH_SIGNUP = "True";
```

Service-by-service the env-var names vary (`OAUTH_*` for Open WebUI, `OPENID_*` for some, `SSO_*` for Vaultwarden). The abstraction handles only the secret-bearing var via `secretEnvName`; the rest stay in the service module where per-service quirks live.

### 5. Python services — set `SSL_CERT_FILE`

Python services (`httpx` / `requests` / `urllib3`) use `certifi` by default, not the system trust store, so they reject Caddy's local CA without:

```nix
SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
```

See `.claude/skills/gotcha-python-certifi-bypass-system-trust/` for the underlying gotcha.

### 6. Deploy

```sh
just rebuild
```

## Web-UI-managed consumers (PocketBase / Beszel)

For services that configure OAuth in their own admin UI rather than via env vars, **only steps 1–3 apply** — no `EnvironmentFile` wiring on the service side. The raw secret sits at `/run/secrets/oidc-<n>-client-secret` for paste-into-admin when configuring the consumer. The env-file template still generates and is just unused; cost is microscopic.

## What stays manual and why

| Manual step | Why |
|---|---|
| PBKDF2 hash generation | Authelia's hash uses random salt; re-running on the same raw produces a different hash. Not amenable to declarative regeneration. `just generate-oidc-key` collapses the two CLI invocations into one |
| Per-service systemd unit name + env-var convention | The abstraction can't divine `chat` → `open-webui`, and OIDC env-var naming is too varied across services to abstract (`OAUTH_*`, `OPENID_*`, `SSO_*`, custom). Both stay in the service module where they're discoverable |

## Verification after deploy

```sh
# Authelia loaded the client (hash substituted from sops):
sudo journalctl -u authelia-* -n 50 | grep -i 'client.*<name>'

# Service sees the secret:
sudo systemctl show <svc>.service -p Environment | grep -i secret

# End-to-end: open the service in a browser, click login → redirect to auth.nori.lan → log in → returned authenticated.
```
