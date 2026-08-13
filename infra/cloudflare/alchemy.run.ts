import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Output from "alchemy/Output";
import * as State from "alchemy/State";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { cloudflareProviders, mcpProviders, OPERATOR_EMAIL } from "./mcp-environment.ts";
import * as Mcp from "./resources/mcp.ts";

const DAY = 24 * 60 * 60;
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
 * Provisions the binary cache that replaced cache.garnix.io. The CI pi-build
 * job is the fleet's only native aarch64 builder, so it signs and uploads the
 * Pi system closure here; the workstation substitutes it instead of
 * recompiling linux-rpi under binfmt emulation.
 *
 * Reads are public at cache.phibkro.org, writes stay credentialed through the
 * S3 API. That split is what lets the workstation carry a plain substituter
 * URL with no credentials on the machine.
 *
 * Public here means the same thing it means for cache.nixos.org: objects are
 * addressed by store hash and the bucket cannot be listed, so fetching an
 * object requires already knowing its hash. It is not a secret store — anyone
 * who can derive a store path can fetch it — which is why nothing that is
 * actually secret may be built into a published closure.
 *
 * Nothing here is bound to a Worker: `nix copy` speaks S3 directly, so the
 * bucket is the whole surface.
 *
 * Operator: `bun alchemy deploy` (needs `alchemy login` once — Cloudflare auth
 * is operator-owned and cannot run headlessly).
 */
export default Alchemy.Stack(
  "Homelab",
  {
    providers: Layer.merge(cloudflareProviders, mcpProviders),
    state: State.localState(),
  },
  Effect.gen(function* () {
    const cache = yield* Cloudflare.R2Bucket("NixCache", {
      name: "homelab-nix-cache",

      // Norway. Jurisdiction is left at "default" on purpose: the objects are
      // builds of public open-source packages, and an "eu" jurisdiction moves
      // the S3 endpoint to a different hostname for every client.
      locationHint: "weur",

      // The read path. Serving from a domain we own rather than the generated
      // r2.dev hostname means the substituter URL in base.nix survives a move
      // to different storage. The zone is inferred from the hostname.
      domains: [{ name: "cache.phibkro.org", minTLS: "1.2" }],

      lifecycleRules: [
        {
          // Without this the bucket grows without bound: every closure ever
          // built is retained, and nothing else prunes it. Ninety days keeps
          // the kernels a rollback would need while staying inside the free
          // tier. Objects still referenced are simply re-uploaded on the next
          // CI run, so expiry costs a rebuild at worst, never correctness.
          id: "expire-closures",
          enabled: true,
          deleteObjectsTransition: {
            condition: { type: "Age", maxAge: 90 * DAY },
          },
        },
        {
          // An interrupted `nix copy` leaves multipart parts that are billed
          // as storage but are invisible to a bucket listing.
          id: "abort-stale-multipart-uploads",
          enabled: true,
          abortMultipartUploadsTransition: {
            condition: { type: "Age", maxAge: 7 * DAY },
          },
        },
      ],
    });

    const bearerToken = yield* Config.redacted("hindsight_mcp_bearer_token").pipe(Effect.orDie);

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


    // Consumed as GitHub repository variables by .github/workflows/check.yml.
    // The account id is an Output, not a string: it is unknown until deploy
    // time, so it has to be composed with `Output.interpolate` rather than a
    // plain template literal, which would coerce it to "[object Object]".
    return {
      bucket: cache.bucketName,
      endpoint: Output.interpolate`${cache.accountId}.r2.cloudflarestorage.com`,
      hindsight: {
        originDns: HINDSIGHT_ORIGIN_HOSTNAME,
        portalDns: hindsightPortalDns.hostname,
        portalUrl: Output.interpolate`https://${hindsightPortal.hostname}/mcp`,
      },
    };
  }),
);
