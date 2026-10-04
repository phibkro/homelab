# Kwyne model gateway

Use this runbook to activate the gateway, authorize its Worker, log in providers,
or rotate credentials. Run host commands on workstation. Run repository commands
from the reviewed homelab checkout unless a command changes directories.

## Placement and boundaries


the Kwyne Worker → Cloudflare Access → shared tunnel → gateway → broker → providers

| Component | Listener | User and state/config directory |
| --- | --- | --- |
| OMP broker | `127.0.0.1:8765` | `kwyne-auth-broker`; `/var/lib/kwyne-auth-broker` |
| OMP gateway | `127.0.0.1:4000` | `kwyne-auth-gateway`; `/var/lib/kwyne-auth-gateway` |
| Public edge | `https://kwyne-model-gateway.phibkro.org` | Isolated `KwyneGateway` Alchemy stack; existing shared tunnel |

The route file `src/infra/cloudflare/routes/kwyne-model-gateway.json` owns the
hostname and listener ports. The manifest owns placement. Both listeners bind
loopback. Neither listener has a firewall opening or an inventory endpoint.
The existing `mcp-origin-cloudflared` connector owns the entire ingress table.
Do not create another connector for this hostname.

Both services and the login wrapper use the same pinned OMP derivation.
Systemd sets HOME to each private state directory and PI_CONFIG_DIR to `.`.
The pinned OMP joins this folder to HOME; an absolute value duplicates HOME.
The login wrapper uses the same configuration, so its broker vault is identical.
State directories have mode 0700. The broker alone owns the SQLite credential
vault. Never copy, migrate, or read the operator's OMP credential store.
The gateway reads broker snapshots, which contain access tokens but no real
refresh tokens. Its user cannot read the broker's directory.

## Secret sources

All gateway values live in `secrets/workstation-runtime.yaml`.
Do not echo values or put them in command arguments. Disable shell tracing.

| SOPS key | Consumer |
| --- | --- |
| `kwyne-auth-broker-bearer` | Broker and gateway `auth-broker.token`; never the Worker |
| `kwyne-model-gateway-bearer` | Gateway `auth-gateway.token` and Worker `MODEL_GATEWAY_BEARER` |
| `kwyne-model-gateway-access-service-token-id` | Token UUID selected by the Alchemy policy; not the Access client ID |
| `kwyne-model-gateway-access-client-id` | Worker `MODEL_GATEWAY_ACCESS_CLIENT_ID` |
| `kwyne-model-gateway-access-client-secret` | Worker `MODEL_GATEWAY_ACCESS_CLIENT_SECRET` |

The two bearers are already encrypted. The three Access keys are declarations
in `secretspec.toml` until the lead creates the token below. They are not fake
values. Nix consumes only the bearers. Systemd LoadCredential reads root-owned
0400 SOPS files. Each startup installs the documented OMP token files as 0600.
SOPS changes restart the affected units. Do not use OMP's token regeneration:
it changes a derived file rather than the canonical encrypted source.

The lead owns the Access service token through the API. The isolated
`KwyneGateway` Alchemy stack owns DNS, the self-hosted application, and its
sole Service Auth policy. The policy uses `non_identity` and one service-token
UUID rule. No email allow, bypass, or second policy is declared. DNS creation
depends on the application and policy. Alchemy receives only the UUID, not
the client secret. Existing compatibility resource identities stay unchanged.

## First activation

### 1. Activate the reviewed system

Run this operator-only command after the lead lands the commits:

```bash
just rebuild
systemctl is-active kwyne-auth-broker kwyne-auth-gateway mcp-origin-cloudflared
curl --fail --silent --show-error http://127.0.0.1:8765/v1/healthz
curl --fail --silent --show-error http://127.0.0.1:4000/healthz
ss -ltn 'sport = :8765 or sport = :4000'
```

Both socket addresses must be 127.0.0.1. Health does not prove provider login,
Access, the tunnel, or a model call.

### 2. Create the Access service token and store its response

The lead runs this block once in a private terminal. cf replaces the former curl procedure.
`cf_admin` uses the operator's `cf auth login` OAuth profile (`~/.config/cloudflare`); the operator logs in once with
`bun x --no-install cf auth login` from `src/infra/cloudflare`. No API token is involved.
Do not repeat creation after an uncertain result. Inspect metadata with cf service-tokens list instead.
The client secret appears only in the create response.


```bash
set -euo pipefail
set +x
umask 077
export DO_NOT_TRACK=1
ACCOUNT_ID=$(cd src/infra/cloudflare && bun -e 'import { CLOUDFLARE_ACCOUNT_ID } from "./mcp-environment.ts"; console.log(CLOUDFLARE_ACCOUNT_ID)')
export CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID"
cf_admin() {
  (cd src/infra/cloudflare && env -u CLOUDFLARE_API_TOKEN DO_NOT_TRACK=1 bun x --no-install cf "$@")
}
TOKEN_NAME="kwyne-model-gateway-worker-$(date -u +%Y%m%dT%H%M%SZ)"
PRIVATE_DIR=$(mktemp -d)
chmod 700 "$PRIVATE_DIR"
trap 'printf "Protected token response retained at %s/token.json\n" "$PRIVATE_DIR" >&2' EXIT
cf_admin zero-trust access service-tokens create --name "$TOKEN_NAME" --duration 8760h > "$PRIVATE_DIR/token.json"
chmod 600 "$PRIVATE_DIR/token.json"
jq -e '(.id | type == "string") and (.client_id | length > 0) and (.client_secret | length > 0)' "$PRIVATE_DIR/token.json" > /dev/null
jq '.id' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-service-token-id"]'
jq '.client_id' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-client-id"]'
jq '.client_secret' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-client-secret"]'
rm -rf "$PRIVATE_DIR"
trap - EXIT
```

Record the token's expiry, then schedule rotation before that date. Commit the
encrypted file by pathspec after the three writes succeed. If storage fails,
keep the protected response until all three fields are encrypted; never print it.

### 3. Apply only the isolated gateway edge

Use the canonical checkout and its existing local Alchemy state. The gateway
has its own stack, `KwyneGateway`, in `kwyne-gateway.alchemy.run.ts`.

```bash
cd src/infra/cloudflare
bun install --frozen-lockfile
export SECRETSPEC_REASON="Reviewing the isolated Kwyne gateway edge"
bun run plan:kwyne-gateway --detailed
```

The plan must show only `KwyneModelGatewayPolicy`,
`KwyneModelGatewayAccess`, and `KwyneModelGatewayDns` as creates.
The package script selects stage `dev_nori` and SecretSpec scope
`cloudflare-kwyne-gateway`. That scope supplies only the control API token and
the service-token UUID. DNS keeps the existing OAuth credential path.
The stack outputs public IDs only. It never creates a service token or exposes
the client secret.

After that review, apply only this stack:

```bash
bun run deploy:kwyne-gateway
```

Do not run `bun run deploy` for this cutover: it applies the unrelated Homelab
main stack, including its open migration and deletion work below.

For a dependency or shared-provider change, inspect the existing stacks without
applying them:

```bash
bun run plan --detailed
bun run plan:projects --detailed
bun run plan:projects-relay --detailed
bun run plan:dev-share --detailed
```

The package pins Alchemy beta.80, Effect 4.0.0, and matching platform packages.
The new gateway uses native Access resources because it has no previous state.
Existing dev-share compatibility resources retain their established IDs.
Changing their resource types needs an explicit identity-preserving migration.

The scripts set `CI=` before Alchemy. A true inherited CI flag disables
OAuth profile lookup and requires complete native environment credentials.
The MCP API-token scope is separate; it does not supply those DNS credentials.
An empty CI value uses the operator's existing OAuth profile, like `env -u CI`.
Fully declared environment credentials still take precedence. These are operator
scripts, not an authentication convention for a headless CI runner.

A saved `creating` row with no attributes can legitimately plan as `create`.
Before creating, the homelab providers look up the stable remote identity.
They update one matching object, create when none exists, and refuse ambiguity.
Policy identity is its name and decision within its exact application.
The read-only plan does not rewrite that interrupted state or prove apply success.

### 4. Log in the providers (operator only)

Run each command on workstation, and complete its OAuth flow yourself:

```bash
kwyne-auth-broker-login anthropic
kwyne-auth-broker-login openai-codex
kwyne-auth-broker-login opencode-go
sudo systemctl restart kwyne-auth-gateway
```

The wrapper performs sudo, clears the inherited environment, and sets HOME and
PI_CONFIG_DIR. It uses the broker unit's exact OMP executable. It never reads the
operator's OMP configuration or credentials. The broker refreshes these logins.

For a remote terminal, forward the callback ports before running the wrapper:

```bash
ssh -L 54545:127.0.0.1:54545 -L 1455:127.0.0.1:1455 \
  -o ExitOnForwardFailure=yes nori@workstation.saola-matrix.ts.net
kwyne-auth-broker-login anthropic
kwyne-auth-broker-login openai-codex
```

Open the printed authorization URL in your local browser. Anthropic uses port
54545; Codex uses port 1455. If another process owns a callback port, finish or
stop that specific session yourself. Never kill processes by name or user.

### 5. Set the Kwyne Worker secrets

Use the actual deployed Worker name from the Kwyne deployment output.
The `--worker` argument selects that Worker, not a new stage.
These calls use the same `cf auth login` profile as step 2.
The installed beta.12 secret-text handler marks omitted `--text` as secret-kind and reads stdin.
Run from the Homelab root with `cf_admin` and the explicit account export from step 2.

```bash
set -euo pipefail
set +x
export DO_NOT_TRACK=1
read -r -p 'Deployed Kwyne Worker name: ' KWYNE_WORKER_NAME
sops decrypt --extract '["kwyne-model-gateway-bearer"]' secrets/workstation-runtime.yaml | cf_admin workers secrets update MODEL_GATEWAY_BEARER --worker "$KWYNE_WORKER_NAME" --type secret_text
sops decrypt --extract '["kwyne-model-gateway-access-client-id"]' secrets/workstation-runtime.yaml | cf_admin workers secrets update MODEL_GATEWAY_ACCESS_CLIENT_ID --worker "$KWYNE_WORKER_NAME" --type secret_text
sops decrypt --extract '["kwyne-model-gateway-access-client-secret"]' secrets/workstation-runtime.yaml | cf_admin workers secrets update MODEL_GATEWAY_ACCESS_CLIENT_SECRET --worker "$KWYNE_WORKER_NAME" --type secret_text
export MODEL_GATEWAY_URL="https://$(jq -r .hostname src/infra/cloudflare/routes/kwyne-model-gateway.json)"
```

MODEL_GATEWAY_URL is configuration, not a secret. It must be the HTTPS origin
above, with no path, query, credentials, or fragment. Deploy Kwyne with that
value, `KWYNE_SANDBOX=container`, and `KWYNE_HARNESS=omp` using its
`docs/ops/cloudflare-cutover.md` procedure. Never give a Container a provider
credential, broker bearer, gateway bearer, or Access service token.

## Health and acceptance

Check local authentication without printing a token:

```bash
curl --silent --show-error --output /dev/null --write-out '%{http_code}\n' http://127.0.0.1:4000/v1/models
sops decrypt --extract '["kwyne-model-gateway-bearer"]' secrets/workstation-runtime.yaml | \
  jq -Rrs '"header = \"Authorization: Bearer " + rtrimstr("\n") + "\""' | \
  curl --config - --silent --show-error --output /dev/null --write-out '%{http_code}\n' http://127.0.0.1:4000/v1/models
```

The first response must be 401. The second must not be 401. With no provider
credentials, that result proves bearer acceptance only.

Check the public gates after apply. Do not use curl verbose output, which can
print request headers. Do not follow redirects on the denial check.

```bash
URL="https://$(jq -r .hostname src/infra/cloudflare/routes/kwyne-model-gateway.json)"
curl --silent --show-error --output /dev/null --write-out '%{http_code}\n' "$URL/v1/models"
{
  sops decrypt --extract '["kwyne-model-gateway-access-client-id"]' secrets/workstation-runtime.yaml | jq -Rrs '"header = \"CF-Access-Client-Id: " + rtrimstr("\n") + "\""'
  sops decrypt --extract '["kwyne-model-gateway-access-client-secret"]' secrets/workstation-runtime.yaml | jq -Rrs '"header = \"CF-Access-Client-Secret: " + rtrimstr("\n") + "\""'
} | curl --config - --silent --show-error --output /dev/null --write-out '%{http_code}\n' "$URL/v1/models"
{
  sops decrypt --extract '["kwyne-model-gateway-access-client-id"]' secrets/workstation-runtime.yaml | jq -Rrs '"header = \"CF-Access-Client-Id: " + rtrimstr("\n") + "\""'
  sops decrypt --extract '["kwyne-model-gateway-access-client-secret"]' secrets/workstation-runtime.yaml | jq -Rrs '"header = \"CF-Access-Client-Secret: " + rtrimstr("\n") + "\""'
  sops decrypt --extract '["kwyne-model-gateway-bearer"]' secrets/workstation-runtime.yaml | jq -Rrs '"header = \"Authorization: Bearer " + rtrimstr("\n") + "\""'
} | curl --config - --silent --show-error --output /dev/null --write-out '%{http_code}\n' "$URL/v1/models"
```

Expected: Access denial (403 or an Access redirect), gateway 401 with Access
headers alone, then the authenticated local result with both gates. A 530, 502,
or 503 is not evidence of an authentication gate. After provider login, run
Kwyne's `J11b-agent-turn-deployed` gate. Only that real model journey proves
Worker egress, the Access path, streaming, and the subscription credentials.

## Rotation and recovery

### Gateway bearer

Generate a new encrypted source without printing it:

```bash
openssl rand -hex 32 | jq -Rs 'rtrimstr("\n")' | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-bearer"]'
```

Commit the encrypted value, activate the reviewed system, and repeat the
MODEL_GATEWAY_BEARER Worker command. Coordinate the brief mismatch window:
OMP loads the token at startup and accepts only one value. Check both gates.

### Broker bearer

Use the same generation command with `kwyne-auth-broker-bearer`. Commit and
activate, then restart both units together:

```bash
sudo systemctl restart kwyne-auth-broker kwyne-auth-gateway
```

Do not change a Worker secret: the Worker never receives this bearer.

### Access service token

For secret rotation without a policy change, use the current UUID and the step 2 account/auth function.
Access: Service Tokens Edit is required, unverified for the SecretSpec token.
Choose a reviewed UTC overlap deadline. Without that flag, rotate immediately revokes the previous secret.

```bash
set -euo pipefail
set +x
umask 077
export DO_NOT_TRACK=1
TOKEN_ID=$(sops decrypt --extract '["kwyne-model-gateway-access-service-token-id"]' secrets/workstation-runtime.yaml)
read -r -p 'Previous-secret expiry (UTC RFC3339): ' PREVIOUS_SECRET_EXPIRES_AT
PRIVATE_DIR=$(mktemp -d)
chmod 700 "$PRIVATE_DIR"
cf_admin zero-trust access service-tokens rotate "$TOKEN_ID" --previous-client-secret-expires-at "$PREVIOUS_SECRET_EXPIRES_AT" > "$PRIVATE_DIR/token.json"
jq -e '(.client_id | length > 0) and (.client_secret | length > 0)' "$PRIVATE_DIR/token.json" > /dev/null
jq '.client_id' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-client-id"]'
jq '.client_secret' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-client-secret"]'
rm -rf "$PRIVATE_DIR"
```

Commit the encrypted changes and repeat both Access Worker secret pipes before the overlap deadline.
Keep a failed response protected until storage succeeds. Check the public gates and a real model call.
Rotation retains the UUID and does not extend token expiry. For an expiring token, create a replacement with step 2.
Store all three fields, commit, deploy only the `KwyneGateway` policy, and repeat both Access Worker commands.
The policy selects one UUID. Coordinate the short mismatch window and check both gates before deletion.
Use the old UUID from the previous encrypted revision, not the client ID.
Delete only that retired token with the same explicit account and auth:

```bash
read -r -p 'Retired token UUID: ' OLD_TOKEN_ID
cf_admin zero-trust access service-tokens delete "$OLD_TOKEN_ID"
```

Never delete the current policy or create a temporary bypass.

### Provider credentials and data loss

Repeat the operator login commands after revocation or loss. Never import the
operator's credential store. No service-specific OAuth backup leaves the host.
Host-level snapshots can still retain the broker directory; treat them as
credential-bearing private data. Bearers and Access credentials survive in SOPS.

## Failure modes

| Observation | Check and action |
| --- | --- |
| Unit fails before listening | Check `journalctl -u kwyne-auth-broker -u kwyne-auth-gateway --since '-10 minutes'` in a private terminal. Check SOPS installation and token-file ownership; never print the files |
| Gateway starts before broker is ready | Its restart policy retries. Check broker health first; restart the gateway after broker recovery |
| Local authenticated request is 401 | Activate the canonical SOPS value and restart the gateway. Do not regenerate its derived token |
| Public request is 403 or redirects with both Access headers | Check expiry, the service-token UUID rule, and both client values. The UUID differs from the client ID |
| Public request is 401 with both gates | Check that the Worker bearer equals the canonical gateway bearer |
| Cloudflare 502/530 | Check the shared connector, its complete ingress table, gateway health, and DNS tunnel target |
| Alchemy refuses extra policies | Review that exact application's policies. Remove unwanted policies only with operator authority; never relax the sole Service Auth policy |
| Model call reports missing credentials | Complete both dedicated broker logins. Health and model listing do not prove a provider credential |
| Model call reports expired/revoked OAuth | Reauthenticate the affected provider with the pinned wrapper; check broker refresh logs privately |
| Worker requests fail but direct gateway succeeds | Check the three Worker secret names and MODEL_GATEWAY_URL origin. Run the deployed Kwyne gate |

## Evidence boundary

`just check-vm e2e-kwyne-model-gateway` boots the real pinned OMP services with
throwaway SOPS bearers and an empty vault. It checks health, loopback-only binds,
401 without bearer, non-401 with bearer, and state/token-file permissions.
It does not call a provider or Cloudflare. `just check` checks repository
configuration. `just build` builds the workstation system without activation.
Real Access, tunnel delivery, OAuth, and a real model call require the operator
steps above. No source check substitutes for those observations.

## Open items outside this gateway cutover

Read-only plans and identity probes on 2026-10-04 found these existing items.
The isolated gateway stack does not apply them or change their declared intent.

- **Hindsight URL migration.** The Homelab main stack declares
  `https://memory-origin.home.phibkro.org/mcp/chatlog-insights-v1/`, but the
  existing server still uses `https://hindsight-origin.phibkro.org/mcp/chatlog-insights-v1/`.
  The immutable-URL guard refuses that update. Review a separate migration;
  do not change the declared URL back or replace the live server as part of
  this gateway cutover. Its old DNS dependency is also removed in the plan.
- **NixCache retirement.** The main stack omits `NixCache` and plans its deletion.
  That existing retirement is not gateway work. Do not apply the main stack
  to deploy this gateway.
- **Four unresolved operator policies.** Read-only provider probes could not resolve
  `HindsightServerPolicy`, `HindsightPortalPolicy`,
  `HerdrProjectsServerPolicyV3`, or `HerdrProjectsPortalPolicy`.
  Direct application discovery returned seven self-hosted apps and one WARP app,
  with no matching MCP or MCP-portal application. This does not prove the
  policies are absent; their physical identities remain unknown.
  The interrupted `creating` rows have no attributes and still plan as creates.
  Reconciliation cannot proceed until the application materializes; it retries
  that condition, then fails with `McpApplicationNotReady`. After resolution,
  it adopts one matching name/allow policy, refuses duplicates, or creates when
  none exists. Resolve these items separately; no policy was created here.
- **Projects V1/V2 retirement.** `projects.alchemy.run.ts` declares only the
  V3 server and server policy. It omits `HerdrProjectsServer`,
  `HerdrProjectsServerV2`, `HerdrProjectsServerPolicy`, and
  `HerdrProjectsServerPolicyV2`, so its four deletes follow the existing source.
  The V3 server already exists at the declared Funnel URL; its interrupted
  create would adopt and update that server instead of duplicating it.
  Review and apply that projects change separately, not in this cutover.
