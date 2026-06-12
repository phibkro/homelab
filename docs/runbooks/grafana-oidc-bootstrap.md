# Grafana OIDC bootstrap

Switch Grafana from anonymous-Admin (current) to Authelia OIDC. Wave-2 deep-clean output: defense-in-depth on the observability join.

## Why this is different from other operator-tier services

Most operator-audience services (qBittorrent, *arr, ollama, hermes) deliberately rely on tailnet membership as the auth perimeter — layering Authelia on top would duplicate the network gate and make Authelia uptime load-bearing for routine operator workflows.

Grafana's blast radius is higher:

- It's the **observability join** — datasources let it query VictoriaLogs, which holds logs from every service. A tailnet-compromised client at Grafana = read access to the entire fleet's recent operations.
- Anonymous-Admin means there's no per-action attribution if anything were to go wrong.

The trade is: Authelia adds defense-in-depth here, and uptime coupling matters less than for, e.g., qBittorrent because Grafana itself is non-critical (logs/metrics keep being collected even if the dashboard is gated).

Document the principle update in `docs/NETWORK.md` § audience-driven trust model when this lands — note that `audience = "operator"` is the default trust posture, but defense-in-depth on observability/admin-join surfaces is an explicit per-service override.

## Bootstrap

### 1. Generate the OIDC client secret + hash

```sh
just generate-oidc-key ops
```

Two values land in your terminal — the raw secret and the PBKDF2 hash.

### 2. Paste both into sops

```sh
sops secrets/secrets.yaml
```

Add under the existing `oidc-*` entries:

```yaml
oidc-ops-client-secret: '<raw>'
oidc-ops-client-secret-hash: '$pbkdf2-sha512$310000$...'
```

### 3. Edit `modules/services/grafana.nix`

Apply these three changes:

**a.** Add `oidc` to the route declaration:

```nix
nori.lanRoutes.ops = {
  port = 3000;
  runsOn = "aurora";
  exposeOnTailnet = true;
  audience = "operator";
  monitor.path = "/api/health";
  oidc = {
    clientName = "Grafana";
    redirectPath = "/login/generic_oauth";
    secretEnvName = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET";
  };
  dashboard = {
    title = "Ops";
    icon = "si:grafana";
    group = "Admin";
    description = "Cross-source dashboards over logs + metrics.";
  };
};
```

**b.** Replace the `"auth.anonymous"` + `auth.disable_login_form` blocks with `auth.generic_oauth`:

```nix
"auth.generic_oauth" = {
  enabled = true;
  name = "Authelia";
  client_id = "ops";
  # client_secret read at runtime from EnvironmentFile (sops template)
  scopes = "openid profile email groups";
  auth_url = "https://auth.${config.nori.domain}/api/oidc/authorization";
  token_url = "https://auth.${config.nori.domain}/api/oidc/token";
  api_url = "https://auth.${config.nori.domain}/api/oidc/userinfo";
  allow_sign_up = true;
  # Operator account auto-mapped to Admin role; everyone else gets Viewer.
  # Adjust the role-mapping JMESPath when family members onboard.
  role_attribute_path = "contains(groups[*], 'admins') && 'Admin' || 'Viewer'";
};

# Keep the login page; redirect to OIDC by default so the operator
# doesn't see the "Sign in" form first.
auth = {
  oauth_auto_login = true;
  disable_login_form = false;
  disable_signout_menu = false;
};
```

**c.** Wire the EnvironmentFile so Grafana can read the client_secret:

```nix
systemd.services.grafana.serviceConfig = {
  EnvironmentFile = config.sops.templates."oidc-ops-env".path;
  SupplementaryGroups = [ "keys" ];
};
```

The `oidc-ops-env` template is auto-declared by the lan-route effect from the `oidc.secretEnvName = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET"` field.

### 4. Update the header comment

Replace the existing "Auth: anonymous-Admin on the tailnet…" paragraph in `grafana.nix` with the rationale above (observability-join blast radius).

### 5. Rebuild aurora

```sh
just remote aurora rebuild
```

The first rebuild may flag an existing Grafana org/user collision since the DB still has an anonymous-org admin record. If so:

```sh
ssh nori@aurora.saola-matrix.ts.net 'sudo systemctl stop grafana'
ssh nori@aurora.saola-matrix.ts.net 'sudo sqlite3 /var/lib/grafana/data/grafana.db "UPDATE user SET email = '\''operator@home.phibkro.org'\'' WHERE id = 1;"'
ssh nori@aurora.saola-matrix.ts.net 'sudo systemctl start grafana'
```

### 6. Verify

Open `https://ops.home.phibkro.org` — should auto-redirect to Authelia, log in, return to Grafana as the operator user with Admin role.

## Rollback

Revert the grafana.nix changes in git; the sops secrets are harmless to leave (unused). Optional cleanup: delete `oidc-ops-client-secret` + `oidc-ops-client-secret-hash` from sops to keep the secret list tidy.
