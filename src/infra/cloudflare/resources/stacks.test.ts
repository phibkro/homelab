import { describe, expect, test } from "bun:test";
import * as BunServices from "@effect/platform-bun/BunServices";
import { AlchemyContextLive } from "alchemy/AlchemyContext";
import { ArtifactStore, createArtifactStore } from "alchemy/Artifacts";
import * as Cloudflare from "alchemy/Cloudflare";
import { layerNonInteractive } from "alchemy/Interaction";
import * as State from "alchemy/State";
import { evalStack } from "alchemy/Stack";
import * as ConfigProvider from "effect/ConfigProvider";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import homelab from "../alchemy.run.ts";
import projects from "../projects.alchemy.run.ts";
import relay from "../projects-relay.alchemy.run.ts";
import devShare from "../dev-share.alchemy.run.ts";
import kwyneGateway from "../kwyne-gateway.alchemy.run.ts";
import { SelfHostedApplication } from "./access.ts";
import { DnsRecord, McpAccessPolicy, McpPortal, McpServer } from "./mcp.ts";

// Import every real stack, including its real Alchemy/Distilled graph. Do not
// deploy any stack: imports and compilation must work without cloud IO.
describe("Cloudflare stack dependency compatibility", () => {
  for (const [stack, name] of [
    [homelab, "Homelab"],
    [projects, "HerdrProjects"],
    [relay, "HerdrProjectsRelay"],
    [devShare, "CanvasArchitectureWorkbench"],
    [kwyneGateway, "KwyneGateway"],
  ] as const) {
    test(`${name} imports as an unexecuted Effect with its existing identity`, () => {
      expect(Effect.isEffect(stack)).toBe(true);
      expect(stack.stackName).toBe(name);
    });
  }

  test("Homelab declares no resources, leaving Hindsight and NixCache retired", () =>
    Effect.runPromise(
      evalStack(
        homelab,
        (stack) => Effect.sync(() => expect(Object.keys(stack.resources)).toEqual([])),
        { stage: "test" },
      ).pipe(
        Effect.provide(
          Layer.mergeAll(
            AlchemyContextLive,
            State.inMemoryState(),
            Layer.sync(ArtifactStore, createArtifactStore),
            layerNonInteractive(),
          ).pipe(Layer.provideMerge(BunServices.layer)),
        ),
        Effect.provideService(
          ConfigProvider.ConfigProvider,
          ConfigProvider.fromEnvRecord({ CLOUDFLARE_MCP_API_TOKEN: "test-only-api-token" }),
        ),
      ),
    ));

  test("the new gateway has native Access resource types distinct from compatibility resources", () => {
    expect(Cloudflare.Access.Policy.Type).toBe("Cloudflare.Access.Policy");
    expect(Cloudflare.Access.Application.Type).toBe("Cloudflare.Access.Application");
    expect(Cloudflare.Access.Application.Type).not.toBe(SelfHostedApplication.Type);
    expect(Cloudflare.Access.Policy.Type).not.toBe(McpAccessPolicy.Type);
  });

  test("compatibility resources keep their established state-owner types", () => {
    expect(SelfHostedApplication.Type).toBe("Homelab.Cloudflare.SelfHostedAccessApplication");
    expect(DnsRecord.Type).toBe("Homelab.Cloudflare.DnsRecord");
    expect(McpServer.Type).toBe("Homelab.Cloudflare.McpServer");
    expect(McpPortal.Type).toBe("Homelab.Cloudflare.McpPortal");
    expect(McpAccessPolicy.Type).toBe("Homelab.Cloudflare.McpAccessPolicy");
  });
});
