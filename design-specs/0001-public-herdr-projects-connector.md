# Public Herdr projects connector

Status: frozen for the first operator deployment

Recorded on: 2026-08-10

## User journey

From ChatGPT web, the operator connects an OAuth-protected remote MCP server,
lists agents already owned by the local herdr-mcp facade in Herdr session
`projects`, sends an idempotent instruction to one chosen agent, and waits for
that exact turn. The public client cannot create, resume, suspend, destroy, or
administer workstation agents.

## Authority and topology

```text
ChatGPT
  -> projects-mcp.phibkro.org (Cloudflare MCP Portal + operator Access policy)
  -> workstation.saola-matrix.ts.net:10000/mcp (Tailscale Funnel; static origin bearer)
  -> shared named Cloudflare Tunnel connector
  -> workstation tailnet Caddy listener
  -> loopback herdr-mcp Streamable HTTP origin
  -> durable facade journal + Herdr session `projects`
```

Cloudflare OAuth identifies the operator. A distinct fixed bearer credential
authenticates Cloudflare to the origin. The origin rejects missing credentials
before MCP parsing and exposes only the existing-agent projection, so bypassing
the portal cannot widen lifecycle authority.

Herdr owns native topology and runtime observations. Herdr-mcp owns stable
facade IDs, turn idempotency, event cursors, and exact waits. Cloudflare owns
public authentication and the portal projection. The client owns only its
requested instruction and caller-stable idempotency key.

## Workstation custody

The single facade journal is
`/home/nori/.local/state/herdr-mcp/projects/facade.sqlite`. Local stdio clients
and the HTTP origin explicitly share that file; SQLite transactions and the
facade's leases serialize concurrent custody. Execution roots remain under
`/tmp/herdr-mcp-projects` and are not confused with durable facade state.

The origin runs the active `/srv/share/projects/herdr-mcp` checkout because the
required server revision is not yet published and the workstation is its sole
deployment target. This is a deliberate development-source exception to a
store-built service: Nix owns the executable, service sandbox, environment,
secret path, ports, and restart policy, while systemd refuses startup if the
checkout or installed dependency tree is missing. Publishing and pinning the
project can replace this exception later without changing the network contract.

## Public surface

The MCP endpoint is Streamable HTTP at `/mcp` and exposes exactly:

- `agent.list`
- `agent.get`
- `events.read`
- `turn.send`
- `wait`

No arbitrary Herdr command, shell text, environment value, filesystem path,
secret value, lifecycle operation, or unmanaged Herdr tab is exposed.

## Falsifiers and acceptance

1. The real `projects` origin starts against the durable recovered journal and
   reconstructs its agents without stopping older connector processes.
2. Missing origin bearer receives `401` before MCP dispatch.
3. Two real HTTP clients see exactly the five frozen tools, share agent state,
   deduplicate one send key, and wait for the exact turn.
4. Nix evaluation/build proves one inventory-owned endpoint, unique ports,
   secret-file custody, and one shared owner for the complete Tunnel ingress
   table. The Pi and its kernel closure are not part of this deployment.
5. Cloudflare TypeScript compiles and an authenticated Alchemy plan names only
   the intended server, portal, DNS, and Access-policy changes before apply.
6. Public success requires observed OAuth discovery, MCP negotiation, tool
   listing, and a live exact-turn journey through the public hostname. Origin
   health, DNS presence, or an applied infrastructure plan is not transitive
   proof of that journey.
7. Checks not run or provider state not observed are reported explicitly.
