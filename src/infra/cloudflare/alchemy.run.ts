import * as Alchemy from "alchemy";
import * as Output from "alchemy/Output";
import * as State from "alchemy/State";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { cloudflareProviders, mcpProviders, OPERATOR_EMAIL } from "./mcp-environment.ts";
import * as Mcp from "./resources/mcp.ts";

const HINDSIGHT_ORIGIN_HOSTNAME = "memory-origin.home.phibkro.org";
const HINDSIGHT_TUNNEL_HOSTNAME = "hindsight-origin.phibkro.org";
const HINDSIGHT_TUNNEL_TARGET = "9fc33815-3e6c-41dc-9858-8e01fe79ecda.cfargotunnel.com";
// Keep the portal one label below the zone so Cloudflare Universal SSL covers
// it without Advanced Certificate Manager or Total TLS. The origin uses the
// homelab's existing *.home.phibkro.org certificate on the Pi entry plane.
const HINDSIGHT_PORTAL_HOSTNAME = "memory-mcp.phibkro.org";

/**
 * Cloudflare infrastructure for the homelab.
 *
 * The Nix binary cache is intentionally absent: it is owned by Attic on the
 * workstation and reached privately through the Pi entry plane. Cloudflare
 * remains responsible only for resources that genuinely require a public
 * edge.
 *
 * Operator: run `bun run login` once, then use `bun run deploy`. The package
 * script supplies the declared SecretSpec command scope.
 */
export default Alchemy.Stack(
  "Homelab",
  {
    providers: Layer.merge(cloudflareProviders, mcpProviders),
    state: State.localState(),
  },
  Effect.gen(function* () {
    const bearerToken = yield* Config.redacted("HINDSIGHT_MCP_BEARER_TOKEN").pipe(Effect.orDie);

    // Preserve the still-running Tunnel route while the DNS-only Pi origin is
    // being proven. Retiring it is a separate destructive migration, not a
    // rider on the Herdr projects connector deployment.
    yield* Mcp.DnsRecord("HindsightOriginDns", {
      hostname: HINDSIGHT_TUNNEL_HOSTNAME,
      content: HINDSIGHT_TUNNEL_TARGET,
      proxied: true,
      comment: "Managed by homelab Alchemy: Hindsight bearer-authenticated MCP origin",
    });

    const hindsightServer = yield* Mcp.McpServer("HindsightServer", {
      id: "hindsight",
      name: "Hindsight agent memory",
      url: `https://${HINDSIGHT_ORIGIN_HOSTNAME}/mcp/chatlog-insights-v1/`,
      bearerToken,
      description: "Read-only recall and reflect tools over the shared Chatlog insight bank",
    });

    yield* Mcp.McpAccessPolicy("HindsightServerPolicy", {
      name: "Operator can use Hindsight",
      email: OPERATOR_EMAIL,
      application: { type: "mcp", serverId: hindsightServer.serverId },
    });

    const hindsightPortal = yield* Mcp.McpPortal("HindsightPortal", {
      id: "agent-memory",
      name: "Agent memory",
      hostname: HINDSIGHT_PORTAL_HOSTNAME,
      description: "Shared Hindsight memory for Codex, Claude, OMP/pi, ChatGPT, and Claude Web",
      serverIds: [hindsightServer.serverId],
      allowCodeMode: false,
      secureWebGateway: false,
    });

    const hindsightPortalDns = yield* Mcp.DnsRecord("HindsightPortalDns", {
      hostname: HINDSIGHT_PORTAL_HOSTNAME,
      content: "gateway.agents.cloudflare.com",
      proxied: true,
      comment: "Managed by homelab Alchemy: Cloudflare MCP Server Portal",
    });

    yield* Mcp.McpAccessPolicy("HindsightPortalPolicy", {
      name: "Operator can connect agent memory",
      email: OPERATOR_EMAIL,
      dependency: hindsightPortal.portalId,
      application: { type: "mcp_portal", hostname: HINDSIGHT_PORTAL_HOSTNAME },
    });


    return {
      hindsight: {
        originDns: HINDSIGHT_ORIGIN_HOSTNAME,
        portalDns: hindsightPortalDns.hostname,
        portalUrl: Output.interpolate`https://${hindsightPortal.hostname}/mcp`,
      },
    };
  }),
);
