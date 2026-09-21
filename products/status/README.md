# Homelab public status

Failure-independent public status for the explicitly published family service
components in `generated/components.json`. The Nix inventory generates this
file. Edit workload manifests, not the JSON.

```bash
# From the repository root, after changing route publication metadata:
status_json=$(nix build .#status-json --no-link --print-out-paths)
cp "$status_json" products/status/generated/components.json

cd products/status
bun install --frozen-lockfile
bun run check
secretspec run --profile workstation --scope public-status -- \
  bun alchemy plan --stage prod
secretspec run --profile workstation --scope public-status -- \
  bun alchemy deploy --stage prod
```

The plan and deploy commands contact Cloudflare and require a scoped deployment
credential. They are operator-gated and are never run by `nix flake check`.
The first Alchemy plan can create its Cloudflare state store. Thus, the plan
requires explicit mutation approval. SecretSpec supplies the high-entropy
`STATUS_MUTATION_TOKEN` from the `public-status` scope. Alchemy installs the
token as a Cloudflare `secret_text` Worker binding. This token is not a
Cloudflare deployment credential. It has no authority over homelab services.

D1 uses a retain removal policy. If you destroy the stack, the history database
remains.
Non-production stages receive stage-derived Worker and D1 names. They also
receive a `workers.dev` URL. Only the `prod` stage can claim
`status.home.phibkro.org` or install the scheduled probe trigger.

Alchemy owns one Worker custom domain, one D1 database, its migrations, and one
two-minute cron trigger. Public access remains `GET /`, `HEAD /`, and
`GET /api/status`. Operator mutations are POST-only under
`/api/operator/events`. They require the separate bearer token and append
history. No delete or rewrite route exists. The Worker cannot control the
homelab.

## Operator commands

SecretSpec supplies `STATUS_MUTATION_TOKEN` to the repository recipes. The API
URL defaults to production. Set `STATUS_API_URL` for a non-production stage.
Component flags can repeat. If omitted, they select all published components.

```bash
cd "$(git rev-parse --show-toplevel)"
secretspec run --profile workstation --scope public-status -- \
  nix run .#statusctl -- maintenance-start \
    --title "Storage migration" --duration-minutes 90 --component media
secretspec run --profile workstation --scope public-status -- \
  nix run .#statusctl -- maintenance-finish <event-id>

secretspec run --profile workstation --scope public-status -- \
  nix run .#statusctl -- incident-start \
    --title "Playback unavailable" --impact outage \
    --message "Investigating" --component media
secretspec run --profile workstation --scope public-status -- \
  nix run .#statusctl -- incident-update <event-id> \
    --state resolved --message "Playback restored"

# Open before activation. Close only after success.
just rebuild-maintained
just push-maintained adelie
just pi-deploy-maintained
```

If an activation, interruption, or closing API call fails, the maintenance
event stays open. After verification, finish it explicitly. The wrapper prints
the event ID before it runs the command.
