---
name: add-oidc-client
description: USE WHEN bootstrapping a new Authelia OIDC client — stores a NixOS consumer's raw secret in its host SecretSpec domain, keeps a Pi web-UI consumer's raw value in the password manager, and stores only the PBKDF2 verifier in Pi SecretSpec.
---

# Bootstrap a new Authelia OIDC client

OIDC client metadata comes from `endpoints.<name>.oidc` in the service
manifest. The inventory compiler derives the canonical route and Pi Authelia
client projections. Each Nix-managed workload receives only its host-local raw
value. Pi Authelia receives only the PBKDF2 verifier through its production
SecretSpec profile. The service module owns its non-secret OIDC variables and
runtime wiring.

The raw value and verifier must derive from the same password-manager value.
Neither value belongs in committed Nix or an unscoped process environment.

## Steps

### 1. Classify the consumer and store the raw value

Resolve the endpoint's selected host and host kind:

```sh
host="$(nix eval --raw .#lib.noriInventory.routes.<endpoint>.host)"
nix eval --raw ".#lib.noriInventory.hosts.${host}.kind"
```

Generate the raw value in the operator password manager.

For a NixOS consumer, declare its variable under `[profiles.<host>]` in
`secretspec.toml`. Route it to the matching
`secrets/<host>-runtime.yaml` provider, then use the masked prompt:

```sh
secretspec set --profile <host> OIDC_<NAME>_CLIENT_SECRET
```

For a Pi-hosted application configured through its web UI, keep the raw value
in the password manager. Do not add it to Pi SecretSpec. Pi Authelia receives
only the verifier from step 2; the application stores the raw value in its own
state after the manual UI update.

### 2. Generate and store the verifier

Use Authelia's terminal prompt. Do not pass the raw value through
`--password`, because command arguments can be observed:

```sh
nix shell nixpkgs#authelia --command \
  authelia crypto hash generate pbkdf2 \
    --variant sha512 \
    --iterations 310000
```

Store the resulting verifier in the Pi provider:

```sh
cd src/infra/pi
devenv shell -- secretspec set \
  --profile production \
  OIDC_<NAME>_CLIENT_SECRET_HASH
```

Before this command, declare the variable in `src/infra/pi/secretspec.toml` and add
it to the `deployment` scope. Set the same environment-variable name as
`secretHashEnvName` in the manifest OIDC block. The Pi adapter resolves it at
deployment time.

The raw client value and verifier have different recipients. Do not copy both
into one SOPS file.

### 3. Declare the endpoint's `oidc` block

In `src/services/<svc>/manifest.nix`, add OIDC metadata to the endpoint. The
manifest is the single source for routing and public-safe authentication
policy:

```nix
endpoints.<name> = {
  port = N;
  monitor = { };
  oidc = {
    clientName = "Display Name";
    redirectPath = "/path/the/service/uses";
    tokenEndpointAuthMethod = "client_secret_basic";
    secretHashEnvName = "OIDC_<NAME>_CLIENT_SECRET_HASH";
    # Optional overrides:
    # scopes = [ "openid" "profile" "email" "groups" ];
    # authorizationPolicy = "one_factor";
    # secretEnvName = "OAUTH_CLIENT_SECRET";
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
OPENID_PROVIDER_URL = "https://auth.${config.nori.inventory.site.domain}/.well-known/openid-configuration";
OAUTH_CLIENT_ID     = "<name>";
OAUTH_PROVIDER_NAME = "Authelia";
ENABLE_OAUTH_SIGNUP = "True";
```

Service-by-service the env-var names vary (`OAUTH_*` for Open WebUI, `OPENID_*` for some, `SSO_*` for Vaultwarden). The abstraction handles only the secret-bearing var via `secretEnvName`; the rest stay in the service module where per-service quirks live.

### 5. Verify and activate the selected hosts

Verify the repository, derive the affected hosts, and preview the Pi change:

```sh
devenv shell -- just check
devenv shell -- nix run .#deployment-plan -- --workload <service>
devenv shell -- just pi::plan
```

Build every NixOS closure named by the plan. After operator approval, activate
the selected NixOS host in plan order, then deploy the Pi verifier. Use
`just rebuild` only when the consumer runs on the current workstation. Use
`just push <host>` for a remote NixOS consumer. Deploy Pi last:

```sh
# NixOS consumer only: run the applicable command, not both.
just rebuild       # current workstation
just push <host>   # remote NixOS host
pi_target="$(nix eval --raw .#lib.noriInventory.hosts.pi.lanIp)"
PI_DEPLOY_CONFIRM="pi@$pi_target" just pi::deploy
```

For a consumer configured through its web UI, skip step 4. Complete the
applicable consumer-host activation and the Pi deployment. For a NixOS
consumer, read the raw value from
`/run/secrets/oidc-<name>-client-secret`. For a Pi-hosted consumer such as
Beszel, use the password-manager value directly; there is intentionally no raw
OIDC client secret in Pi SecretSpec. Configure client ID `<name>`, then verify
the complete browser login.

## What stays manual and why

| Manual step | Why |
|---|---|
| PBKDF2 verifier generation | Authelia uses a random salt. Generate it from the same raw value through the masked terminal prompt, then store it in the Pi SecretSpec provider. |
| Per-service systemd unit name + env-var convention | The abstraction can't divine `chat` → `open-webui`, and OIDC env-var naming is too varied across services to abstract (`OAUTH_*`, `OPENID_*`, `SSO_*`, custom). Both stay in the service module where they're discoverable |

## Verification after activation

1. Open the service URL in a browser.
2. Select its OIDC login action.
3. Confirm the redirect uses `https://auth.<nori.domain>`.
4. Sign in.
5. Confirm the browser returns to the service as the authenticated user.

For a systemd-wired consumer, also confirm that its unit is active:

```sh
systemctl is-active <svc>.service
```
