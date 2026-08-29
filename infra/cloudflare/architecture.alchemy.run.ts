import * as Alchemy from "alchemy";
import * as Output from "alchemy/Output";
import * as State from "alchemy/State";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import route from "./routes/canvas-plugin-architecture.json" with { type: "json" };
import {
  cloudflareControlDependencies,
  cloudflareProviders,
  mcpProviders,
  OPERATOR_EMAIL,
} from "./mcp-environment.ts";
import * as Access from "./resources/access.ts";
import * as Mcp from "./resources/mcp.ts";

const accessProviders = Access.providers().pipe(Layer.provide(cloudflareControlDependencies));

export default Alchemy.Stack(
  "CanvasArchitectureWorkbench",
  {
    providers: Layer.mergeAll(cloudflareProviders, mcpProviders, accessProviders),
    state: State.localState(),
  },
  Effect.gen(function* () {
    const access = yield* Access.SelfHostedApplication("ArchitectureAccess", {
      name: "Canvas plugin architecture workbench",
      hostname: route.hostname,
      email: OPERATOR_EMAIL,
      sessionDuration: "24h",
    });

    const dns = yield* Mcp.DnsRecord("ArchitectureDns", {
      hostname: route.hostname,
      content: `${route.tunnelId}.cfargotunnel.com`,
      proxied: true,
      comment: "Managed by homelab Alchemy: Access-protected Canvas architecture workbench",
      dependency: access.applicationId,
    });

    return {
      hostname: dns.hostname,
      url: Output.interpolate`https://${dns.hostname}`,
      accessApplicationId: access.applicationId,
    };
  }),
);
