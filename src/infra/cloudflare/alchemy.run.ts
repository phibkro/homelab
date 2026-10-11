import * as Alchemy from "alchemy";
import * as State from "alchemy/State";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import { cloudflareProviders, mcpProviders } from "./mcp-environment.ts";

/**
 * The main stack declares no resources. Hindsight and the NixCache R2 bucket
 * were retired; Nix builds use public binary substituters directly. The stack
 * keeps its provider and state boundary so removed resources are deleted by
 * `bun run deploy` and a new public-edge resource has a home.
 */
export default Alchemy.Stack(
  "Homelab",
  {
    providers: Layer.merge(cloudflareProviders, mcpProviders),
    state: State.localState(),
  },
  Effect.succeed({}),
);
