import * as Alchemy from "alchemy";
import * as Output from "alchemy/Output";
import * as State from "alchemy/State";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { cloudflareProviders, mcpProviders, OPERATOR_EMAIL } from "./mcp-environment.ts";
import * as Mcp from "./resources/mcp.ts";

const PROJECTS_ORIGIN_HOSTNAME = "projects-origin.phibkro.org";
const PROJECTS_PORTAL_HOSTNAME = "projects-mcp.phibkro.org";
const MCP_TUNNEL_TARGET = "9fc33815-3e6c-41dc-9858-8e01fe79ecda.cfargotunnel.com";
const PROJECTS_FUNNEL_URL = "https://workstation.saola-matrix.ts.net:10000/mcp";

/**
 * Isolated public projection for the workstation's existing Herdr agents.
 * Keeping this in its own stack prevents a connector rollout from reconciling
 * unrelated Hindsight or R2 resources.
 */
export default Alchemy.Stack(
  "HerdrProjects",
  {
    providers: Layer.merge(cloudflareProviders, mcpProviders),
    state: State.localState(),
  },
  Effect.gen(function* () {
    const bearerToken = yield* Config.redacted("herdr_projects_mcp_bearer_token").pipe(
      Effect.orDie,
    );

    const server = yield* Mcp.McpServer("HerdrProjectsServerV3", {
      id: "herdr-projects-v3",
      name: "Herdr projects agents",
      url: PROJECTS_FUNNEL_URL,
      bearerToken,
    description:
        "Inspect and instruct existing facade-owned agents in the workstation projects session through its authenticated MCP origin",
    });

    const originDns = yield* Mcp.DnsRecord("HerdrProjectsOriginDns", {
      hostname: PROJECTS_ORIGIN_HOSTNAME,
      content: MCP_TUNNEL_TARGET,
      proxied: true,
      comment: "Managed by homelab Alchemy: bearer-authenticated Herdr MCP origin",
    });

    yield* Mcp.McpAccessPolicy("HerdrProjectsServerPolicyV3", {
      name: "Operator can use Herdr projects",
      email: OPERATOR_EMAIL,
      application: { type: "mcp", serverId: server.serverId },
    });

    const portal = yield* Mcp.McpPortal("HerdrProjectsPortal", {
      id: "agent-projects",
      name: "Agent projects",
      hostname: PROJECTS_PORTAL_HOSTNAME,
      description: "Existing workstation project agents for ChatGPT and other operator clients",
      serverIds: [server.serverId],
      allowCodeMode: false,
      secureWebGateway: false,
    });

    const portalDns = yield* Mcp.DnsRecord("HerdrProjectsPortalDns", {
      hostname: PROJECTS_PORTAL_HOSTNAME,
      content: "gateway.agents.cloudflare.com",
      proxied: true,
      comment: "Managed by homelab Alchemy: Cloudflare MCP Server Portal",
    });

    yield* Mcp.McpAccessPolicy("HerdrProjectsPortalPolicy", {
      name: "Operator can connect agent projects",
      email: OPERATOR_EMAIL,
      dependency: portal.portalId,
      application: { type: "mcp_portal", hostname: PROJECTS_PORTAL_HOSTNAME },
    });

    return {
      originDns: originDns.hostname,
      portalDns: portalDns.hostname,
      portalUrl: Output.interpolate`https://${portal.hostname}/mcp`,
    };
  }),
);
