import { describe, expect, test } from "bun:test";
import * as Credentials from "@distilled.cloud/cloudflare/Credentials";
import { CloudflareEnvironment } from "alchemy/Cloudflare";
import * as Provider from "alchemy/Provider";
import { noopSession } from "alchemy/Report";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";
import { HttpClient, HttpClientResponse } from "effect/http";
import { SelfHostedApplication, SelfHostedApplicationProvider, type SelfHostedApplicationProps } from "./access.ts";

const news: SelfHostedApplicationProps = {
  mode: "service-auth", name: "Test gateway", hostname: "gateway.example.test", sessionDuration: "24h",
  serviceTokenId: "f570199e-5bd4-4dd4-87b1-18a5c6168419",
};
const app = { id: "existing-app", name: news.name, domain: news.hostname, type: "self_hosted" };
const policy = {
  id: "existing-policy", name: "Test gateway: service auth", decision: "non_identity",
  include: [{ service_token: { token_id: news.serviceTokenId } }], exclude: [], require: [],
};
const interrupted = { status: "creating", props: news }; // Deliberately no attr/output, as in real checkpoints.
type App = typeof app;
type Policy = typeof policy;

const fixture = (initialApps: App[], initialPolicies: Policy[], denied = false) => {
  let apps = initialApps;
  let policies = initialPolicies;
  const requests: { method: string; path: string }[] = [];
  const client = HttpClient.make((request, url) => Effect.sync(() => {
    const path = url.pathname.replace("/accounts/test-account", "");
    requests.push({ method: request.method, path });
    if (denied) return HttpClientResponse.fromWeb(request, Response.json({ success: false, result: null }, { status: 403 }));
    let result: unknown;
    const policyList = /^\/access\/apps\/[^/]+\/policies$/.test(path);
    if (request.method === "GET") {
      if (path !== "/access/apps" && !policyList) throw new Error("Unexpected fixture GET: " + path);
      result = path === "/access/apps" ? apps : policies;
      const count = path === "/access/apps" ? apps.length : policies.length;
      return HttpClientResponse.fromWeb(request, Response.json({ success: true, result, result_info: { count, page: 1, total_count: count } }));
    }
    if (request.method === "POST" && path === "/access/apps") {
      const created = { ...app, id: "created-app" };
      apps = [created]; result = created;
    } else if (request.method === "POST" && policyList) {
      const created = { ...policy, id: "created-policy" };
      policies = [...policies, created]; result = created;
    } else if (request.method === "PUT" && /^\/access\/apps\/[^/]+\/policies\/[^/]+$/.test(path)) {
      const id = path.split("/").at(-1)!;
      const updated = { ...policy, id };
      policies = policies.map((old) => old.id === id ? updated : old); result = updated;
    } else if (request.method === "PUT" && /^\/access\/apps\/[^/]+$/.test(path)) {
      const id = path.split("/").at(-1)!;
      result = { ...app, id };
    } else {
      throw new Error("Unexpected fixture request: " + request.method + " " + path);
    }
    return HttpClientResponse.fromWeb(request, Response.json({ success: true, result }));
  }));
  const dependencies = Layer.mergeAll(
    Layer.succeed(HttpClient.HttpClient, client),
    Credentials.fromApiToken({ apiToken: "test-only-api-token", apiBaseUrl: "https://example.test" }),
    Layer.succeed(CloudflareEnvironment, Effect.succeed({
      type: "apiToken" as const, apiToken: Redacted.make("test-only-api-token"), accountId: "test-account",
      source: { type: "env" as const, details: "test" },
    })),
  );
  const run = (output?: SelfHostedApplication["Attributes"]) => Effect.gen(function* () {
    const provider = yield* Provider.Provider<SelfHostedApplication>(SelfHostedApplication.Type);
    return yield* provider.reconcile({ id: "Gateway", fqn: "Gateway", instanceId: "test-instance", news,
      olds: interrupted.props, output, bindings: [], session: { ...noopSession, note: () => Effect.void } });
  }).pipe(Effect.provide(SelfHostedApplicationProvider().pipe(Layer.provide(dependencies))));
  const read = () => Effect.gen(function* () {
    const provider = yield* Provider.Provider<SelfHostedApplication>(SelfHostedApplication.Type);
    if (!provider.read) throw new Error("Expected Access read hook");
    return yield* provider.read({ id: "Gateway", fqn: "Gateway", instanceId: "test-instance", olds: interrupted.props, output: undefined });
  }).pipe(Effect.provide(SelfHostedApplicationProvider().pipe(Layer.provide(dependencies))));
  return { requests, run, read };
};

// The real provider, request encoding and response decoding run against an injected native HttpClient.
describe("Access interrupted-create adoption", () => {
  test("read-only probe recovers an interrupted app/policy without writes", async () => {
    const api = fixture([app], [policy]);
    expect(await Effect.runPromise(api.read())).toEqual({ applicationId: app.id, policyId: policy.id, hostname: news.hostname });
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
  test("read-only probe reports a genuinely absent hostname", async () => {
    const api = fixture([], []);
    expect(await Effect.runPromise(api.read())).toBeUndefined();
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
  test("read-only probe refuses ambiguous hostname ownership", async () => {
    const api = fixture([app, { ...app, id: "other-app" }], [policy]);
    const error = await Effect.runPromise(Effect.flip(api.read()));
    expect(error._tag).toBe("AmbiguousAccessIdentity");
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
  test("creates app and policy only when neither stable identity exists", async () => {
    const api = fixture([], []);
    const result = await Effect.runPromise(api.run());
    expect(result.applicationId).toBe("created-app"); expect(result.policyId).toBe("created-policy");
    expect(api.requests.filter((request) => request.method === "POST").map((request) => request.path)).toEqual([
      "/access/apps", "/access/apps/created-app/policies",
    ]);
  });
  test("adopts and updates one existing app and policy without duplicate POSTs", async () => {
    const api = fixture([app], [policy]);
    expect(await Effect.runPromise(api.run())).toEqual({ applicationId: app.id, policyId: policy.id, hostname: news.hostname });
    expect(api.requests.some((request) => request.method === "POST")).toBe(false);
    expect(api.requests.filter((request) => request.method === "PUT").map((request) => request.path)).toEqual([
      "/access/apps/existing-app", "/access/apps/existing-app/policies/existing-policy",
    ]);
  });
  test("a lost saved ID still checks stable identity before creating", async () => {
    const api = fixture([app], [policy]);
    const result = await Effect.runPromise(api.run({ applicationId: "lost-app", policyId: "lost-policy", hostname: news.hostname }));
    expect(result.applicationId).toBe(app.id); expect(result.policyId).toBe(policy.id);
    expect(api.requests.some((request) => request.method === "POST")).toBe(false);
  });
  test("refuses two hostname matches before any write", async () => {
    const api = fixture([app, { ...app, id: "other-app" }], [policy]);
    const error = await Effect.runPromise(Effect.flip(api.run()));
    expect(error._tag).toBe("AmbiguousAccessIdentity"); expect(error.kind).toBe("application");
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
  test("refuses two policy name/decision matches before any write", async () => {
    const api = fixture([app], [policy, { ...policy, id: "other-policy" }]);
    const error = await Effect.runPromise(Effect.flip(api.run()));
    expect(error._tag).toBe("AmbiguousAccessIdentity"); expect(error.kind).toBe("policy");
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
  test("same name with a different decision is not silently adopted", async () => {
    const api = fixture([app], [{ ...policy, decision: "bypass" }]);
    const error = await Effect.runPromise(Effect.flip(api.run()));
    expect(error._tag).toBe("UnexpectedAccessPolicies");
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
  test("permission failure is not converted into absence or a create", async () => {
    const api = fixture([], [], true);
    const error = await Effect.runPromise(Effect.flip(api.run()));
    expect(error._tag).toBe("AccessRequestError");
    expect(api.requests.every((request) => request.method === "GET")).toBe(true);
  });
});
