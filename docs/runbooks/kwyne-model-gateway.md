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
| Public edge | `https://kwyne-model-gateway.phibkro.org` | Homelab Alchemy stack; existing shared tunnel |

The route file `src/infra/cloudflare/routes/kwyne-model-gateway.json` owns the
hostname and listener ports. The manifest owns placement. Both listeners bind
loopback. Neither listener has a firewall opening or an inventory endpoint.
The existing `mcp-origin-cloudflared` connector owns the entire ingress table.
Do not create another connector for this hostname.

Both services and the login wrapper use the same pinned OMP derivation.
Systemd sets HOME and PI_CONFIG_DIR to each service's private state directory.
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

The lead owns the Access service token through the API. The Homelab Alchemy
stack owns DNS, the self-hosted application, and its sole policy. The policy
uses Service Auth (`non_identity`) and one `service_token.token_id` rule.
No email allow, bypass, or second policy is permitted. Apply refuses extra
policies; it does not delete operator resources. DNS creation depends on the
policy. Alchemy receives only the UUID, not the client secret.

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

The lead runs this block once. It needs the existing Cloudflare control token
with Access service-token write permission. Use a private terminal, not an
agent transcript. Do not run this block again to diagnose an uncertain result:
inspect token names in the Access dashboard first. The client secret appears
only in the create response.

```bash
set -euo pipefail
set +x
umask 077
ACCOUNT_ID=$(cd src/infra/cloudflare && bun -e 'import { CLOUDFLARE_ACCOUNT_ID } from "./mcp-environment.ts"; console.log(CLOUDFLARE_ACCOUNT_ID)')
TOKEN_NAME="kwyne-model-gateway-worker-$(date -u +%Y%m%dT%H%M%SZ)"
PRIVATE_DIR=$(mktemp -d)
trap 'rm -f "$PRIVATE_DIR/cloudflare.conf" "$PRIVATE_DIR/create.json"; printf "Protected token response retained at %s/token.json\n" "$PRIVATE_DIR" >&2' EXIT
{
  printf 'header = "Authorization: Bearer '
  sops decrypt --extract '["cloudflare_mcp_api_token"]' secrets/operator-tools.yaml | tr -d '\n'
  printf '"\n'
} > "$PRIVATE_DIR/cloudflare.conf"
jq -n --arg name "$TOKEN_NAME" '{name: $name, duration: "8760h"}' > "$PRIVATE_DIR/create.json"
curl --fail --silent --show-error --config "$PRIVATE_DIR/cloudflare.conf" \
  --header 'Content-Type: application/json' --request POST \
  --data-binary @"$PRIVATE_DIR/create.json" \
  --output "$PRIVATE_DIR/token.json" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/service_tokens"
jq -e '.success == true and (.result.id | type == "string") and (.result.client_id | length > 0) and (.result.client_secret | length > 0)' \
  "$PRIVATE_DIR/token.json" > /dev/null
jq '.result.id' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-service-token-id"]'
jq '.result.client_id' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-client-id"]'
jq '.result.client_secret' "$PRIVATE_DIR/token.json" | sops set --value-stdin secrets/workstation-runtime.yaml '["kwyne-model-gateway-access-client-secret"]'
rm -rf "$PRIVATE_DIR"
trap - EXIT
```

Record the token's expiry, then schedule rotation before that date. Commit the
encrypted file by pathspec after the three writes succeed. If storage fails,
keep the protected response until all three fields are encrypted; never print it.

### 3. Apply the Homelab edge

Apply from the canonical checkout with its existing local Alchemy state.
Do not apply from an empty worktree: that loses resource ownership history.

```bash
cd src/infra/cloudflare
bun install --frozen-lockfile
bun run plan
bun run plan:projects
bun run plan:projects-relay
bun run plan:dev-share
```

The package scripts select the existing stage `dev_nori` explicitly. Do not
use the new Alchemy CLI's implicit stage. The four plans must show no replacement
or deletion of an existing resource before any apply. Review every plan.

The main plan's gateway additions are `KwyneModelGatewayAccess` and
`KwyneModelGatewayDns`. The main script supplies the workstation SecretSpec
profile and `cloudflare-main` scope. Its output contains public IDs only.
The existing Hindsight, projects, relay, and dev-share resources must remain.

After that review, apply only the main stack for the new gateway:

```bash
bun run deploy
```

The package pins Alchemy beta.80, Effect 4.0.0, and the matching platform
packages. Mixed prerelease dependencies failed at import before this alignment.
The Access compatibility resource retains the existing resource type and output
IDs. Native Access resources use a different state identity, so replacing the
compatibility resource here can replace existing applications.

### 4. Log in the providers (operator only)

Run each command on workstation, and complete its OAuth flow yourself:

```bash
kwyne-auth-broker-login anthropic
kwyne-auth-broker-login openai-codex
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
The `--name` argument selects that Worker; it does not select a new stage.
These commands consume plaintext through pipes, not arguments or echo.

```bash
HOMELAB=/srv/share/projects/homelab
cd /srv/share/projects/kwyne
read -r -p 'Deployed Kwyne Worker name: ' KWYNE_WORKER_NAME
sops decrypt --extract '["kwyne-model-gateway-bearer"]' "$HOMELAB/secrets/workstation-runtime.yaml" | bun x wrangler secret put MODEL_GATEWAY_BEARER --name "$KWYNE_WORKER_NAME"
sops decrypt --extract '["kwyne-model-gateway-access-client-id"]' "$HOMELAB/secrets/workstation-runtime.yaml" | bun x wrangler secret put MODEL_GATEWAY_ACCESS_CLIENT_ID --name "$KWYNE_WORKER_NAME"
sops decrypt --extract '["kwyne-model-gateway-access-client-secret"]' "$HOMELAB/secrets/workstation-runtime.yaml" | bun x wrangler secret put MODEL_GATEWAY_ACCESS_CLIENT_SECRET --name "$KWYNE_WORKER_NAME"
export MODEL_GATEWAY_URL="https://$(jq -r .hostname "$HOMELAB/src/infra/cloudflare/routes/kwyne-model-gateway.json")"
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

Create a replacement with step 2, with a new timestamped name. Store all three
fields, commit, apply the Homelab policy, and repeat both Access Worker commands.
The policy always selects one UUID, so coordinate the short mismatch window.
Check the public gates and a real model call before revoking the old token.
Use its old UUID from the previous encrypted revision, not the client ID.
Delete that specific token through the Access dashboard or the API endpoint
`DELETE /accounts/{account_id}/access/service_tokens/{old_token_uuid}`.
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
