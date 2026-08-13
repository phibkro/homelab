# Hindsight agent memory

This runbook activates and operates the shared Hindsight memory service on
`workstation`.

## Exposure model

| Surface | Address | Boundary |
| --- | --- | --- |
| Hindsight API | `127.0.0.1:9077` | Host only; includes the mutating REST API |
| Control Plane UI | `127.0.0.1:9999` | Raw standalone UI; host only |
| UI proxy | `127.0.0.1:9998` | Normalizes forwarded headers for Tailscale Serve on port 10443 |
| MCP origin | `100.81.5.122:9078` | Tailnet hop from the DNS-only Pi entry plane; exact MCP path plus bearer token |
| MCP Portal | `https://memory-mcp.phibkro.org/mcp` | Publicly routable, Cloudflare Access/OAuth authenticated |

The public route exposes only Hindsight's stateless `recall` and `reflect` MCP
tools. It does not expose the Control Plane, REST API, or `retain`. Cloudflare's
MCP Portal is the client-facing URL; it authenticates the operator and supplies
the private bearer credential when it calls the origin. The origin returns 404
for every other path and for requests without that credential.

Resource ownership is split deliberately:

- NixOS owns the local services, the Pi Caddy route, the DNS-only DDNS record,
  and encrypted credentials.
- Tailscale Serve owns the UI's tailnet-only listener. Its node-wide config is
  shared with other tools, so this runbook adds/removes only port 10443 and
  never calls `tailscale serve reset`.
- Alchemy owns the Portal DNS record, MCP server, MCP Portal, and their Access
  policies. The existing `cloudflare-ddns` service owns
  `memory-origin.home.phibkro.org` and keeps it pointed at the residential WAN.

The MCP origin deliberately uses the established DNS-only Pi entry plane.
Cloudflare's MCP server synchronizer did not reach a same-zone proxied Tunnel
CNAME even though direct public requests succeeded; Caddy access logs confirmed
that no synchronization request arrived. The DNS-only route enters through Pi
Caddy and crosses the tailnet to the bearer-checking workstation listener.

## Preflight

Run from the repository root:

```sh
git status --short
nix build --option substituters https://cache.nixos.org \
  .#nixosConfigurations.workstation.config.system.build.toplevel
(cd infra/cloudflare && bun run typecheck && bun run plan)
tailscale serve status
```

The new MCP AI-controls endpoints currently reject the Alchemy OAuth grant,
even though the same grant manages DNS and R2 successfully. Create a dedicated
Cloudflare API token scoped to account `phibkro` with:

- `MCP Portals Write`
- `Access: Apps and Policies Edit`
- account resource `phibkro` only

Store it without placing the value in shell history:

```sh
cd /srv/share/projects/homelab
sops secrets/apps.yaml
```

Add it as `cloudflare_mcp_api_token`. The package scripts decrypt it directly
into the process environment. Only the MCP server, portal, and Access-policy
providers receive this credential; DNS and the existing R2 cache retain their
Alchemy OAuth credentials.

Review the Alchemy plan. It should add only the Hindsight DNS, MCP, and Access
resources; the existing R2 cache must not be replaced.

## First activation

An ad-hoc user unit currently owns port 9077. Stop it immediately before the
first NixOS activation; the same pg0 instance is reused, so no data migration is
required.

```sh
systemctl --user disable --now chatlog-hindsight.service
just rebuild
sudo systemctl status \
  chatlog-hindsight.service \
  hindsight-control-plane.service \
  hindsight-mcp-origin.service
```

If activation fails before the NixOS API starts, restore the existing pilot:

```sh
systemctl --user enable --now chatlog-hindsight.service
```

Add only the new tailnet UI listener, preserving the existing Serve mappings:

```sh
sudo tailscale serve --bg --yes --https=10443 http://127.0.0.1:9998
tailscale serve status
```

The UI is then available from a tailnet device at
`https://workstation.saola-matrix.ts.net:10443/`.

Once all local services are healthy, create the edge resources:

```sh
cd infra/cloudflare
bun run plan
bun run deploy
```

Alchemy receives the origin bearer token from sops. Do not copy it into an
Alchemy source file, Cloudflare dashboard field, command argument, or log.

## Verify boundaries

Confirm that the API and UI listeners are loopback-only and that only the
bearer-checking MCP origin also listens on the workstation tailnet address:

```sh
sudo ss -ltnp | rg ':(9077|9078|9998|9999)\b'
```

Unauthenticated origin requests deliberately look absent:

```sh
curl -i https://memory-origin.home.phibkro.org/mcp/chatlog-insights-v1/
curl -i https://memory-origin.home.phibkro.org/
```

Both must return 404. Test the private origin path without exposing the token in
the process list:

```sh
cd infra/cloudflare
sops exec-env ../../secrets/apps.yaml \
  'curl -i -H "Authorization: Bearer $hindsight_mcp_bearer_token" \
  https://memory-origin.home.phibkro.org/mcp/chatlog-insights-v1/'
```

An MCP response may reject a plain GET as a protocol error; it must no longer be
the proxy's 404. Finally, open the Portal URL in a private browser window and
confirm that Cloudflare Access requires the operator identity before reaching
MCP.

## Connect clients

Use this remote MCP URL in clients that support custom remote connectors:

```text
https://memory-mcp.phibkro.org/mcp
```

In ChatGPT, add it as a custom connector. In Claude Web, add it as a custom
connector/integration. Complete the Cloudflare Access browser authorization as
the operator account. Product plan and workspace-admin policy can hide these
features; in that case the same URL still works from Codex, Claude Code, and
other MCP clients that support remote OAuth.

Keep local harnesses on the direct loopback MCP URL when they run on
`workstation`; the Portal is primarily the authenticated bridge for web-hosted
clients.

## Rollback

Remove only the Hindsight Serve listener:

```sh
sudo tailscale serve --https=10443 off
```

Stop the new local surface by reverting the workload assignment and rebuilding
`workstation`. Restore the prior ad-hoc unit only if the NixOS service no longer
owns port 9077.

Cloudflare removal is a separate external-state action. Review
`(cd infra/cloudflare && bun run plan)` after reverting the Hindsight Alchemy
resources, then deploy that reviewed change. Do not run `bun run destroy`: the
stack also owns the production Nix binary cache.

## Data durability

The Hindsight bank is currently a derived pilot index. Canonical harness
sessions and web exports remain in Chatlog and can be re-ingested. A live copy
of embedded PostgreSQL is not a valid backup; add a quiesced `pg_dump` workflow
before treating new retained memories as irreplaceable state.
