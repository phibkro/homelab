import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Output from "alchemy/Output";
import * as Provider from "alchemy/Provider";
import * as State from "alchemy/State";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Schema from "effect/Schema";
import gatewayRoute from "./routes/kwyne-model-gateway.json" with { type: "json" };
import devShareRoute from "./routes/dev-share.json" with { type: "json" };
import { cloudflareControlDependencies, cloudflareProviders } from "./mcp-environment.ts";
import { ServiceTokenId } from "./resources/access.ts";
import * as Mcp from "./resources/mcp.ts";

// Capture the API-token credentials in only the native Access lifecycle
// providers. DNS retains the ordinary Cloudflare OAuth credential path.
const accessProviders = Layer.effect(
  Cloudflare.Providers,
  Provider.collection([Cloudflare.Access.Policy, Cloudflare.Access.Application]),
).pipe(
  Layer.provide(
    Layer.mergeAll(
      Cloudflare.Access.PolicyProvider(),
      Cloudflare.Access.ApplicationProvider(),
    ).pipe(Layer.provide(cloudflareControlDependencies)),
  ),
);
const dnsProviders = Mcp.dnsProviders().pipe(Layer.provide(cloudflareProviders));
const decodeServiceTokenId = Schema.decodeEffect(ServiceTokenId);

/** Gateway-only ownership; the existing shared tunnel and service token are inputs. */
export default Alchemy.Stack(
  "KwyneGateway",
  {
    providers: Layer.mergeAll(cloudflareProviders, dnsProviders, accessProviders),
    state: State.localState(),
  },
  Effect.gen(function* () {
    // Invalid deployment configuration is fatal at the stack boundary.
    const serviceTokenId = yield* Config.String("KWYNE_MODEL_GATEWAY_ACCESS_SERVICE_TOKEN_ID").pipe(
      Effect.flatMap(decodeServiceTokenId),
      Effect.orDie,
    );
    const policy = yield* Cloudflare.Access.Policy("KwyneModelGatewayPolicy", {
      name: "Kwyne model gateway ServiceAuth",
      decision: "non_identity",
      include: [{ serviceToken: { tokenId: serviceTokenId } }],
    });
    const application = yield* Cloudflare.Access.Application("KwyneModelGatewayAccess", {
      name: "Kwyne model gateway",
      type: "self_hosted",
      domain: gatewayRoute.hostname,
      policies: [policy],
      appLauncherVisible: false,
    });
    const dns = yield* Mcp.DnsRecord("KwyneModelGatewayDns", {
      hostname: gatewayRoute.hostname,
      content: `${devShareRoute.tunnelId}.cfargotunnel.com`,
      proxied: true,
      comment: "Managed by homelab Alchemy: ServiceAuth-protected Kwyne model gateway",
      // Application creation already depends on the sole reusable policy.
      dependency: application.applicationId,
    });

    return {
      hostname: dns.hostname,
      url: Output.interpolate`https://${dns.hostname}`,
      accessApplicationId: application.applicationId,
      accessPolicyId: policy.policyId,
      dnsRecordId: dns.recordId,
    };
  }),
);
