import * as CloudflareCredentials from "@distilled.cloud/cloudflare/Credentials";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";
import * as Mcp from "./resources/mcp.ts";

export const CLOUDFLARE_ACCOUNT_ID = "d2319ba5e93bf509a478951e90496374";
export const OPERATOR_EMAIL = "philib.krogh@gmail.com";

export const cloudflareProviders = Cloudflare.providers();

const mcpControlDependencies = Layer.unwrap(
  Config.redacted("cloudflare_mcp_api_token").pipe(
    Effect.map((apiToken) =>
      Layer.merge(
        CloudflareCredentials.fromApiToken({ apiToken: Redacted.value(apiToken) }),
        Layer.succeed(Cloudflare.CloudflareEnvironment, {
          type: "apiToken",
          apiToken,
          accountId: CLOUDFLARE_ACCOUNT_ID,
          source: { type: "env", details: "cloudflare_mcp_api_token" },
        }),
      ),
    ),
  ),
).pipe(Layer.orDie);

const mcpDnsProviders = Mcp.dnsProviders().pipe(Layer.provide(cloudflareProviders));
const mcpControlProviders = Mcp.controlProviders().pipe(
  Layer.provide(mcpControlDependencies),
);

export const mcpProviders = Layer.merge(mcpDnsProviders, mcpControlProviders);

