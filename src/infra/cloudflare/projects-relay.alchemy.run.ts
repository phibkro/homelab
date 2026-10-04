import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as State from "alchemy/State";
import type { RelaySession } from "./workers/herdr-projects-relay.ts";
import { cloudflareProviders } from "./mcp-environment.ts";

export default Alchemy.Stack(
  "HerdrProjectsRelay",
  {
    providers: cloudflareProviders,
    state: State.localState(),
  },
  Effect.gen(function* () {
    const relay = yield* Cloudflare.Worker("HerdrProjectsRelay", {
      name: "herdr-projects-relay",
      main: "./workers/herdr-projects-relay.ts",
      compatibility: { date: "2026-08-10" },
      workersDev: true,
      env: {
        RelaySession: Cloudflare.DurableObject<RelaySession>("RelaySession"),
        RELAY_TOKEN: Config.Redacted("HERDR_PROJECTS_MCP_BEARER_TOKEN"),
      },
      observability: {
        enabled: true,
        logs: { enabled: true, invocationLogs: true },
      },
    });
    return { url: relay.url };
  }),
);
