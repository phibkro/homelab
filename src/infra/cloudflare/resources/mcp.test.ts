import { describe, expect, test } from "bun:test";
import { Credentials } from "@distilled.cloud/cloudflare/Credentials";
import * as Retry from "@distilled.cloud/cloudflare/Retry";
import { CloudflareEnvironment } from "alchemy/Cloudflare";
import * as Provider from "alchemy/Provider";
import type { ScopedPlanStatusSession } from "alchemy/Report";
import * as Cause from "effect/Cause";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Fiber from "effect/Fiber";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";
import { HttpClient, HttpClientResponse } from "effect/http";
import { controlProviders, McpAccessPolicy, McpServer } from "./mcp.ts";

const accountId = "00000000000000000000000000000000";
const apiBaseUrl = "https://cloudflare.invalid/client/v4";
const serverPath = "/client/v4/accounts/" + accountId + "/access/ai-controls/mcp/servers";
const appsPath = "/client/v4/accounts/" + accountId + "/access/apps";
const appId = "11111111-1111-4111-8111-111111111111";
const otherAppId = "22222222-2222-4222-8222-222222222222";
const policyPath = appsPath + "/" + appId + "/policies";
const ServerProvider = Provider.Provider<McpServer>(McpServer.Type);
const PolicyProvider = Provider.Provider<McpAccessPolicy>(McpAccessPolicy.Type);
const session: ScopedPlanStatusSession = {
  emit: () => Effect.void,
  done: () => Effect.void,
  note: () => Effect.void,
};
const lifecycle = { id: "checkpoint", fqn: "checkpoint", instanceId: "existing-instance", session, bindings: [] };

// These are the real saved creating shapes, with synthetic values only. Apply
// resolves current news but passes olds: undefined for a creating checkpoint.
const serverCheckpoint = {
  status: "creating" as const,
  props: {
    id: "requested-server", name: "Managed MCP", url: "https://origin.invalid/mcp",
    bearerToken: Redacted.make("synthetic-origin-token"), description: "managed configuration",
  },
  attr: undefined,
};
const policyCheckpoint = {
  status: "creating" as const,
  props: { name: "Managed operator", email: "operator@example.invalid", application: { type: "mcp" as const } },
  attr: undefined,
};
const serverNews = serverCheckpoint.props;
const policyNews = {
  ...policyCheckpoint.props,
  application: { ...policyCheckpoint.props.application, serverId: "remote-server" },
};
const remoteServer = (id: string, name = serverNews.name, hostname = serverNews.url) => ({
  id, name, hostname, auth_type: "bearer", prompts: [], tools: [], status: "ready",
});
const remotePolicy = (id: string, name = policyNews.name, decision = "allow") => ({
  id, name, decision, include: [{ email: { email: "old@example.invalid" } }], exclude: [], require: [],
});
const remoteApp = (id = appId, serverId = "remote-server") => ({
  id, type: "mcp", destinations: [{ type: "via_mcp_server_portal", mcp_server_id: serverId }],
});

interface RequestObservation { method: string; path: string; page: number; body: string | undefined }
interface Reply { result?: unknown; status?: number; errors?: { code: number; message: string }[] }
type Responder = (request: RequestObservation) => Reply;

const harness = (respond: Responder) => {
  const requests: RequestObservation[] = [];
  const client = HttpClient.make((request, url) => Effect.sync(() => {
    const observation = {
      method: request.method, path: url.pathname, page: Number(url.searchParams.get("page") ?? 1),
      body: request.body._tag === "Uint8Array" ? new TextDecoder().decode(request.body.body) : undefined,
    };
    requests.push(observation);
    const reply = respond(observation);
    const status = reply.status ?? 200;
    return HttpClientResponse.fromWeb(request, new Response(JSON.stringify({
      success: status >= 200 && status < 300,
      result: reply.result,
      errors: reply.errors ?? [],
      result_info: { page: observation.page },
    }), { status, headers: { "content-type": "application/json" } }));
  }));
  return { requests, layer: providerLayer(client) };
};

const providerLayer = (client: HttpClient.HttpClient) => controlProviders().pipe(Layer.provideMerge(Layer.mergeAll(
  Layer.succeed(HttpClient.HttpClient, client),
  Layer.succeed(Credentials, Effect.succeed({ type: "apiToken", apiToken: Redacted.make("synthetic-control-token"), apiBaseUrl })),
  Layer.succeed(CloudflareEnvironment, Effect.succeed({
    type: "apiToken", apiToken: Redacted.make("synthetic-control-token"), accountId, source: { type: "env" },
  })),
  Layer.succeed(Retry.Retry, { while: () => false }),
)));
const reconcileServer = (output?: McpServer["Attributes"]) => Effect.gen(function* () {
  const provider = yield* ServerProvider;
  return yield* provider.reconcile({ ...lifecycle, news: serverNews, olds: undefined, output });
});
const reconcilePolicy = (output?: McpAccessPolicy["Attributes"]) => Effect.gen(function* () {
  const provider = yield* PolicyProvider;
  return yield* provider.reconcile({ ...lifecycle, news: policyNews, olds: undefined, output });
});
const appReply = (request: RequestObservation): Reply | undefined => request.method === "GET" && request.path === appsPath
  ? { result: request.page === 1 ? [remoteApp(), remoteApp(otherAppId, "other-server")] : [] }
  : undefined;

// The actual provider and generated SDK serialize and decode every request.
// No global fetch, module mock, live credentials, or cloud IO is involved.
describe("MCP interrupted-creation reconciliation", () => {
  for (const count of [0, 1, 2]) {
    test("server exact-name discovery with " + count + " matches", async () => {
      const h = harness((request) => {
        if (request.method === "GET" && request.path === serverPath) {
          return { result: request.page === 1 ? [remoteServer("unrelated", "Other"), ...Array.from({ length: count }, (_, i) => remoteServer("existing-" + i))] : [] };
        }
        if (request.method === "POST" && request.path === serverPath) return { result: remoteServer(serverNews.id) };
        if (request.method === "PUT" && request.path === serverPath + "/existing-0") return { result: remoteServer("existing-0") };
        if (request.method === "POST" && request.path.endsWith("/sync")) return { result: { status: "ready" } };
        throw new Error("Unexpected request: " + request.method + " " + request.path);
      });
      const result = await Effect.runPromise(Effect.scoped((count > 1 ? Effect.flip(reconcileServer()) : reconcileServer()).pipe(Effect.provide(h.layer))));
      if (count > 1) {
        expect(result).toMatchObject({ _tag: "McpIdentityAmbiguous", resource: "server", count });
        expect(h.requests.every((r) => r.method === "GET")).toBe(true);
      } else {
        expect(result).toEqual({ serverId: count === 0 ? serverNews.id : "existing-0", name: serverNews.name, url: serverNews.url, status: "ready" });
        expect(h.requests.filter((r) => r.method === "POST" && r.path === serverPath)).toHaveLength(count === 0 ? 1 : 0);
        const update = h.requests.find((r) => r.method === "PUT");
        if (count === 1) {
          expect(update?.path).toBe(serverPath + "/existing-0");
          expect(update?.body).toContain('"name":"Managed MCP"');
          expect(update?.body).toContain('"description":"managed configuration"');
          expect(update?.body).toContain('"auth_credentials":"synthetic-origin-token"');
        }
      }
    });

    test("policy scoped name AND decision discovery with " + count + " matches", async () => {
      expect(policyCheckpoint.props.application).toEqual({ type: "mcp" });
      const h = harness((request) => {
        const apps = appReply(request);
        if (apps) return apps;
        if (request.method === "GET" && request.path === policyPath) {
          return { result: request.page === 1 ? [remotePolicy("wrong-decision", policyNews.name, "deny"), ...Array.from({ length: count }, (_, i) => remotePolicy("policy-" + i))] : [] };
        }
        if (request.method === "POST" && request.path === policyPath) return { result: remotePolicy("created-policy") };
        if (request.method === "PUT" && request.path === policyPath + "/policy-0") return { result: remotePolicy("policy-0") };
        throw new Error("Unexpected request: " + request.method + " " + request.path);
      });
      const result = await Effect.runPromise(Effect.scoped((count > 1 ? Effect.flip(reconcilePolicy()) : reconcilePolicy()).pipe(Effect.provide(h.layer))));
      if (count > 1) {
        expect(result).toMatchObject({ _tag: "McpIdentityAmbiguous", resource: "policy", count });
        expect(h.requests.every((r) => r.method === "GET")).toBe(true);
      } else {
        expect(result).toEqual({ applicationId: appId, policyId: count === 0 ? "created-policy" : "policy-0" });
        expect(h.requests.filter((r) => r.method === "POST")).toHaveLength(count === 0 ? 1 : 0);
        const mutation = h.requests.find((r) => r.method !== "GET");
        expect(mutation?.body).toContain('"decision":"allow"');
        expect(mutation?.body).toContain('"email":"operator@example.invalid"');
        expect(mutation?.body).toContain('"session_duration":"24h"');
      }
      expect(h.requests.some((r) => r.path.includes(otherAppId + "/policies"))).toBe(false);
    });
  }

  test("immutable server URL mismatch fails before any mutation", async () => {
    const h = harness((request) => ({ result: request.page === 1 ? [remoteServer("existing", serverNews.name, "https://different.invalid/mcp")] : [] }));
    const error = await Effect.runPromise(Effect.scoped(Effect.flip(reconcileServer()).pipe(Effect.provide(h.layer))));
    expect(error).toMatchObject({ _tag: "McpServerUrlImmutable", serverId: "existing" });
    expect(h.requests.every((r) => r.method === "GET")).toBe(true);
  });

  test("recorded server ID is authoritative even if a different server has the desired name", async () => {
    const h = harness((request) => {
      if (request.method === "GET" && request.path === serverPath + "/saved") return { result: remoteServer("saved", "Renamed") };
      if (request.method === "PUT" && request.path === serverPath + "/saved") return { result: remoteServer("saved") };
      if (request.path === serverPath + "/saved/sync") return { result: { status: "ready" } };
      throw new Error("Name enumeration must not override saved ID");
    });
    const result = await Effect.runPromise(Effect.scoped(reconcileServer({ serverId: "saved", name: "Renamed", url: serverNews.url, status: "ready" }).pipe(Effect.provide(h.layer))));
    expect(result.serverId).toBe("saved");
    expect(h.requests.some((r) => r.path === serverPath)).toBe(false);
  });

  test("recorded policy ID beats an earlier name match and remote decision drift", async () => {
    const h = harness((request) => {
      const apps = appReply(request);
      if (apps) return apps;
      if (request.method === "GET" && request.path === policyPath) return { result: request.page === 1 ? [remotePolicy("wrong-name-match"), remotePolicy("saved", "Renamed", "deny")] : [] };
      if (request.method === "PUT" && request.path === policyPath + "/saved") return { result: remotePolicy("saved") };
      throw new Error("Saved ID was not respected");
    });
    const result = await Effect.runPromise(Effect.scoped(reconcilePolicy({ applicationId: appId, policyId: "saved" }).pipe(Effect.provide(h.layer))));
    expect(result).toEqual({ applicationId: appId, policyId: "saved" });
    expect(h.requests.some((r) => r.method === "POST")).toBe(false);
  });

  test("lost saved server ID adopts unique stable name before any create", async () => {
    const h = harness((request) => {
      if (request.method === "GET" && request.path === serverPath + "/lost") return { status: 404, errors: [{ code: 404, message: "MCP server not found" }] };
      if (request.method === "GET" && request.path === serverPath) return { result: request.page === 1 ? [remoteServer("replacement-id")] : [] };
      if (request.method === "PUT" && request.path === serverPath + "/replacement-id") return { result: remoteServer("replacement-id") };
      if (request.path === serverPath + "/replacement-id/sync") return { result: { status: "ready" } };
      throw new Error("Lost saved ID must not cause creation");
    });
    const result = await Effect.runPromise(Effect.scoped(reconcileServer({ serverId: "lost", name: serverNews.name, url: serverNews.url, status: "ready" }).pipe(Effect.provide(h.layer))));
    expect(result.serverId).toBe("replacement-id");
    expect(h.requests.filter((r) => r.method === "POST" && r.path === serverPath)).toHaveLength(0);
    expect(h.requests.some((r) => r.method === "PUT" && r.path.endsWith("/replacement-id"))).toBe(true);
  });

  test("lost saved policy ID adopts scoped name and decision before any create", async () => {
    const h = harness((request) => {
      const apps = appReply(request);
      if (apps) return apps;
      if (request.method === "GET" && request.path === policyPath) return { result: request.page === 1 ? [remotePolicy("replacement-id"), remotePolicy("wrong-decision", policyNews.name, "deny")] : [] };
      if (request.method === "PUT" && request.path === policyPath + "/replacement-id") return { result: remotePolicy("replacement-id") };
      throw new Error("Lost saved policy ID must not cause creation");
    });
    const result = await Effect.runPromise(Effect.scoped(reconcilePolicy({ applicationId: appId, policyId: "lost" }).pipe(Effect.provide(h.layer))));
    expect(result).toEqual({ applicationId: appId, policyId: "replacement-id" });
    expect(h.requests.some((r) => r.method === "POST")).toBe(false);
    expect(h.requests.some((r) => r.method === "PUT" && r.path.endsWith("/replacement-id"))).toBe(true);
  });

  test("saved application identity cannot be silently rebound", async () => {
    const h = harness((request) => appReply(request) ?? (() => { throw new Error("No policy request allowed after identity mismatch"); })());
    const error = await Effect.runPromise(Effect.scoped(Effect.flip(reconcilePolicy({ applicationId: otherAppId, policyId: "saved" })).pipe(Effect.provide(h.layer))));
    expect(error).toMatchObject({ _tag: "McpApplicationIdentityChanged" });
  });

  test("duplicates on a later page prevent adoption", async () => {
    const h = harness((request) => {
      const apps = appReply(request);
      if (apps) return apps;
      if (request.path === policyPath && request.method === "GET") return { result: request.page <= 2 ? [remotePolicy("page-" + request.page)] : [] };
      throw new Error("Duplicate discovery must not mutate");
    });
    const error = await Effect.runPromise(Effect.scoped(Effect.flip(reconcilePolicy()).pipe(Effect.provide(h.layer))));
    expect(error).toMatchObject({ _tag: "McpIdentityAmbiguous", count: 2 });
    expect(h.requests.every((r) => r.method === "GET")).toBe(true);
  });

  test("server authorization failure propagates without retry or creation", async () => {
    const h = harness(() => ({ status: 403, errors: [{ code: 10000, message: "Forbidden" }] }));
    const error = await Effect.runPromise(Effect.scoped(Effect.flip(reconcileServer()).pipe(Effect.provide(h.layer))));
    expect(error._tag).not.toBe("McpApplicationNotReady");
    expect(h.requests).toHaveLength(1);
    expect(h.requests[0]?.method).toBe("GET");
  });

  test("policy authorization failure propagates without retry or creation", async () => {
    const h = harness(() => ({ status: 403, errors: [{ code: 10000, message: "Forbidden" }] }));
    const error = await Effect.runPromise(Effect.scoped(Effect.flip(reconcilePolicy()).pipe(Effect.provide(h.layer))));
    expect(error._tag).not.toBe("McpApplicationNotReady");
    expect(h.requests).toHaveLength(1);
    expect(h.requests[0]?.method).toBe("GET");
  });

  test("missing policy response ID fails instead of persisting fake attributes", async () => {
    const h = harness((request) => {
      const apps = appReply(request);
      if (apps) return apps;
      if (request.method === "GET") return { result: [] };
      return { result: { name: policyNews.name, decision: "allow" } };
    });
    const error = await Effect.runPromise(Effect.scoped(Effect.flip(reconcilePolicy()).pipe(Effect.provide(h.layer))));
    expect(error._tag).toBe("SchemaError");
  });

  test("sync failure after create retries by discovered identity, not another create", async () => {
    let existing = false;
    let syncs = 0;
    const h = harness((request) => {
      if (request.method === "GET") return { result: request.page === 1 && existing ? [remoteServer("created-server")] : [] };
      if (request.path === serverPath && request.method === "POST") { existing = true; return { result: remoteServer("created-server") }; }
      if (request.method === "PUT") return { result: remoteServer("created-server") };
      if (request.path.endsWith("/sync")) return { result: ++syncs === 1 ? { status: "error", error: "discovery failed" } : { status: "ready" } };
      throw new Error("Unexpected request");
    });
    const result = await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      const failed = yield* Effect.flip(reconcileServer());
      expect(failed._tag).toBe("McpServerSyncFailed");
      return yield* reconcileServer();
    }).pipe(Effect.provide(h.layer))));
    expect(result.serverId).toBe("created-server");
    expect(h.requests.filter((r) => r.method === "POST" && r.path === serverPath)).toHaveLength(1);
  });

  test("interruption cancels native HTTP discovery and runs cleanup once", async () => {
    await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      const started = yield* Deferred.make<AbortSignal>();
      let releases = 0;
      const client = HttpClient.make((_request, _url, signal) => Effect.gen(function* () {
        yield* Deferred.succeed(started, signal);
        return yield* Effect.never;
      }).pipe(Effect.ensuring(Effect.sync(() => { releases++; }))));
      const fiber = yield* reconcileServer().pipe(Effect.provide(providerLayer(client)), Effect.forkChild);
      const signal = yield* Deferred.await(started);
      yield* Fiber.interrupt(fiber);
      const exit = yield* Fiber.await(fiber);
      expect(Exit.isFailure(exit) && Cause.hasInterrupts(exit.cause)).toBe(true);
      expect(signal.aborted).toBe(true);
      expect(releases).toBe(1);
    })));
  });

  test("HTTP client defects propagate, never masquerade as no match", async () => {
    const defect = new Error("synthetic defect");
    const client = HttpClient.make(() => Effect.die(defect));
    const exit = await Effect.runPromise(Effect.scoped(Effect.exit(reconcileServer()).pipe(Effect.provide(providerLayer(client)))));
    expect(Exit.isFailure(exit) && Cause.hasDies(exit.cause)).toBe(true);
  });
  for (const count of [0, 1, 2]) {
    test("readonly server name probe shares reconciliation selection: " + count, async () => {
      const h = harness((request) => {
        if (request.method !== "GET" || request.path !== serverPath) throw new Error("Read mutated cloud state");
        return { result: request.page === 1 ? Array.from({ length: count }, (_, i) => remoteServer("observed-" + i)) : [] };
      });
      const probe = Effect.gen(function* () {
        const provider = yield* ServerProvider;
        if (!provider.read) return yield* Effect.die(new Error("Provider has no read hook"));
        return yield* provider.read({ ...lifecycle, olds: serverCheckpoint.props, output: undefined });
      });
      const result = await Effect.runPromise(Effect.scoped((count > 1 ? Effect.flip(probe) : probe).pipe(Effect.provide(h.layer))));
      if (count > 1) expect(result).toMatchObject({ _tag: "McpIdentityAmbiguous", count });
      else if (count === 0) expect(result).toBeUndefined();
      else expect(result).toMatchObject({ serverId: "observed-0" });
      expect(h.requests.every((r) => r.method === "GET")).toBe(true);
    });

    test("readonly policy concrete selector shares reconciliation selection: " + count, async () => {
      const h = harness((request) => {
        const apps = appReply(request);
        if (apps) return apps;
        if (request.method !== "GET" || request.path !== policyPath) throw new Error("Read mutated or searched another app");
        return { result: request.page === 1 ? Array.from({ length: count }, (_, i) => remotePolicy("observed-" + i)) : [] };
      });
      const probe = Effect.gen(function* () {
        const provider = yield* PolicyProvider;
        if (!provider.read) return yield* Effect.die(new Error("Provider has no read hook"));
        return yield* provider.read({ ...lifecycle, olds: policyNews, output: undefined });
      });
      const result = await Effect.runPromise(Effect.scoped((count > 1 ? Effect.flip(probe) : probe).pipe(Effect.provide(h.layer))));
      if (count > 1) expect(result).toMatchObject({ _tag: "McpIdentityAmbiguous", count });
      else if (count === 0) expect(result).toBeUndefined();
      else expect(result).toEqual({ applicationId: appId, policyId: "observed-0" });
      expect(h.requests.every((r) => r.method === "GET")).toBe(true);
    });
  }

  test("historical stripped policy selector remains unknown without cloud IO", async () => {
    const h = harness(() => { throw new Error("A stripped selector must not query the cloud"); });
    const result = await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
      // The engine discovers providers by resource type and supplies persisted
      // plain props. Its ResourceLike boundary permits historical incomplete
      // shapes; this intentionally exercises that actual boundary without a cast.
      const provider = yield* Provider.findProviderByType(McpAccessPolicy.Type);
      if (!provider.read) return yield* Effect.die(new Error("Provider has no read hook"));
      return yield* provider.read({ ...lifecycle, olds: policyCheckpoint.props, output: undefined });
    }).pipe(Effect.provide(h.layer))));
    expect(result).toBeUndefined();
    expect(h.requests).toHaveLength(0);
  });

  test("malformed server response fails strict native decoding before mutation", async () => {
    const h = harness(() => ({ result: [{ id: "existing", name: serverNews.name, hostname: 42 }] }));
    const exit = await Effect.runPromise(Effect.scoped(Effect.exit(reconcileServer()).pipe(Effect.provide(h.layer))));
    expect(Exit.isFailure(exit)).toBe(true);
    expect(h.requests).toHaveLength(1);
    expect(h.requests[0]?.method).toBe("GET");
  });

});
