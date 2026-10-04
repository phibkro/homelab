import { describe, expect, test } from "bun:test";
import * as Effect from "effect/Effect";
import homelab from "../alchemy.run.ts";
import projects from "../projects.alchemy.run.ts";
import relay from "../projects-relay.alchemy.run.ts";
import devShare from "../dev-share.alchemy.run.ts";
import { SelfHostedApplication } from "./access.ts";
import { DnsRecord, McpAccessPolicy, McpPortal, McpServer } from "./mcp.ts";

// Import every real stack, including its real Alchemy/Distilled graph. Do not
// execute any stack effect: imports must work without credentials or cloud IO.
describe("Cloudflare stack dependency compatibility", () => {
  for (const [stack, name] of [
    [homelab, "Homelab"],
    [projects, "HerdrProjects"],
    [relay, "HerdrProjectsRelay"],
    [devShare, "CanvasArchitectureWorkbench"],
  ] as const) {
    test(`${name} imports as an unexecuted Effect with its existing identity`, () => {
      expect(Effect.isEffect(stack)).toBe(true);
      expect(stack.stackName).toBe(name);
    });
  }

  test("compatibility resources keep their established state-owner types", () => {
    expect(SelfHostedApplication.Type).toBe("Homelab.Cloudflare.SelfHostedAccessApplication");
    expect(DnsRecord.Type).toBe("Homelab.Cloudflare.DnsRecord");
    expect(McpServer.Type).toBe("Homelab.Cloudflare.McpServer");
    expect(McpPortal.Type).toBe("Homelab.Cloudflare.McpPortal");
    expect(McpAccessPolicy.Type).toBe("Homelab.Cloudflare.McpAccessPolicy");
  });
});
