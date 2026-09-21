import { describe, expect, test } from "bun:test";
import {
  components,
  escapeHtml,
  overallState,
  publicStatus,
  renderHtml,
  type StoredComponentStatus,
  type StoredEvent,
  type StoredEventUpdate,
} from "../src/status.ts";
import {
  hasValidBearerToken,
  validateCreateEvent,
  validateEventUpdate,
} from "../src/operator.ts";
import { handleRequest, probeComponent } from "../src/worker.ts";
import type { WorkerEnv } from "../alchemy.run.ts";

const emptyDatabase = {
  prepare: () => ({
    all: async () => ({ results: [] }),
  }),
} as unknown as D1Database;
const env = { DB: emptyDatabase, MUTATION_TOKEN: "test-token" } as WorkerEnv;

describe("public inventory projection", () => {
  test("contains only the explicitly published components", () => {
    expect(components.map(({ id }) => id)).toEqual([
      "audio",
      "media",
      "requests",
    ]);
    expect(Object.keys(components[0] ?? {}).sort()).toEqual([
      "description",
      "id",
      "title",
      "url",
    ]);
  });

  test("defaults to unknown without inventing an operational result", () => {
    const status = publicStatus([], new Date("2026-07-22T00:00:00Z"));
    expect(status.overall).toBe("unknown");
    expect(status.services.every(({ state }) => state === "unknown")).toBeTrue();
  });

  test("active maintenance overrides probes and terminal updates preserve history", () => {
    const events: StoredEvent[] = [
      {
        id: "maintenance-1",
        kind: "maintenance",
        title: "Media rebuild",
        impact: null,
        created_at: "2026-07-22T00:00:00Z",
      },
    ];
    const updates: StoredEventUpdate[] = [
      {
        event_id: "maintenance-1",
        sequence: 1,
        state: "in_progress",
        message: "Applying a new generation",
        starts_at: "2026-07-22T00:00:00Z",
        expected_end_at: "2026-07-22T01:00:00Z",
        created_at: "2026-07-22T00:00:00Z",
      },
    ];
    const status = publicStatus(
      [
        {
          component_id: "media",
          state: "operational",
          checked_at: "2026-07-22T00:00:00Z",
          latency_ms: 20,
          status_code: 200,
        },
      ],
      new Date("2026-07-22T00:05:00Z"),
      events,
      [{ event_id: "maintenance-1", component_id: "media" }],
      updates,
    );
    expect(status.services.find(({ id }) => id === "media")?.state).toBe(
      "maintenance",
    );
    expect(status.events[0]).toMatchObject({
      id: "maintenance-1",
      components: ["media"],
      state: "in_progress",
    });

    updates.push({
      event_id: "maintenance-1",
      sequence: 2,
      state: "completed",
      message: "Generation active",
      starts_at: null,
      expected_end_at: null,
      created_at: "2026-07-22T00:10:00Z",
    });
    const completed = publicStatus(
      [],
      new Date("2026-07-22T00:10:00Z"),
      events,
      [{ event_id: "maintenance-1", component_id: "media" }],
      updates,
    );
    expect(completed.services.find(({ id }) => id === "media")?.state).toBe(
      "unknown",
    );
    expect(completed.events).toHaveLength(1);
  });
});

describe("normalized status", () => {
  test("outage wins over maintenance and degradation", () => {
    expect(
      overallState([
        { state: "operational" },
        { state: "maintenance" },
        { state: "outage" },
      ]),
    ).toBe("outage");
  });

  test("does not expose stored diagnostics in the public schema", () => {
    const row: StoredComponentStatus = {
      component_id: "audio",
      state: "operational",
      checked_at: "2026-07-22T00:00:00Z",
      latency_ms: 42,
      status_code: 200,
    };
    const encoded = JSON.stringify(publicStatus([row]));
    expect(encoded).not.toContain("latency_ms");
    expect(encoded).not.toContain("status_code");
    expect(encoded).not.toContain("component_id");
  });
});

describe("HTML boundary", () => {
  test("escapes inventory and database-derived strings", () => {
    expect(escapeHtml(`<script>alert("x")</script>`)).toBe(
      "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;",
    );
    const html = renderHtml({
      version: 2,
      generatedAt: `"><script>bad()</script>`,
      overall: "unknown",
      events: [
        {
          id: "event-1",
          kind: "incident",
          title: "<img src=x>",
          state: "investigating",
          impact: "degraded",
          message: "<script>latest()</script>",
          components: ["media"],
          createdAt: "2026-07-22T00:00:00Z",
          updatedAt: "2026-07-22T00:00:00Z",
          startsAt: null,
          expectedEndAt: null,
          updates: [
            {
              state: "investigating",
              message: "<script>update()</script>",
              createdAt: "2026-07-22T00:00:00Z",
            },
          ],
        },
      ],
      services: [
        {
          id: "bad",
          title: "<img src=x>",
          description: "& unsafe",
          url: "https://example.invalid",
          state: "unknown",
          checkedAt: null,
        },
      ],
    });
    expect(html).not.toContain("<script>bad()");
    expect(html).not.toContain("<script>update()");
    expect(html).not.toContain("<img src=x>");
  });
});

describe("HTTP boundary", () => {
  test("serves only the allowlisted public JSON schema", async () => {
    const response = await handleRequest(
      new Request("https://status.home.phibkro.org/api/status"),
      env,
      new Date("2026-07-22T00:00:00Z"),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("application/json");
    expect(response.headers.get("Content-Security-Policy")).toContain(
      "default-src 'none'",
    );
    const body = (await response.json()) as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual([
      "events",
      "generatedAt",
      "overall",
      "services",
      "version",
    ]);
    expect(JSON.stringify(body)).not.toContain("status_code");
  });

  test("fails closed for unknown paths and mutation methods", async () => {
    const missing = await handleRequest(
      new Request("https://status.home.phibkro.org/internal"),
      env,
    );
    expect(missing.status).toBe(404);
    const missingMutation = await handleRequest(
      new Request("https://status.home.phibkro.org/internal", {
        method: "POST",
      }),
      env,
    );
    expect(missingMutation.status).toBe(404);


    const mutation = await handleRequest(
      new Request("https://status.home.phibkro.org/api/status", {
        method: "POST",
      }),
      env,
    );
    expect(mutation.status).toBe(405);
    expect(mutation.headers.get("Allow")).toBe("GET, HEAD");
  });

  test("HEAD returns headers without a response body", async () => {
    const response = await handleRequest(
      new Request("https://status.home.phibkro.org/", { method: "HEAD" }),
      env,
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("");
  });

  test("event-history failure does not erase healthy probe results", async () => {
    const database = {
      prepare: (sql: string) => ({
        all: async () => {
          if (sql.includes("component_status")) {
            return {
              results: [
                {
                  component_id: "media",
                  state: "operational",
                  checked_at: "2026-07-22T00:00:00Z",
                  latency_ms: 20,
                  status_code: 200,
                },
              ],
            };
          }
          throw new Error("event tables temporarily unavailable");
        },
      }),
    } as unknown as D1Database;
    const response = await handleRequest(
      new Request("https://status.home.phibkro.org/api/status"),
      { DB: database, MUTATION_TOKEN: "test-token" } as WorkerEnv,
    );
    const body = (await response.json()) as {
      services: Array<{ id: string; state: string }>;
    };
    expect(body.services.find(({ id }) => id === "media")?.state).toBe(
      "operational",
    );
  });
});

describe("operator mutation boundary", () => {
  test("uses bearer authentication without accepting prefixes", async () => {
    expect(
      await hasValidBearerToken(
        new Request("https://status.home.phibkro.org/api/operator/events", {
          headers: { Authorization: "Bearer test-token" },
        }),
        "test-token",
      ),
    ).toBeTrue();
    expect(
      await hasValidBearerToken(
        new Request("https://status.home.phibkro.org/api/operator/events", {
          headers: { Authorization: "Bearer test" },
        }),
        "test-token",
      ),
    ).toBeFalse();
  });

  test("rejects invalid components and cross-kind states", () => {
    expect(
      validateCreateEvent({
        kind: "incident",
        title: "Outage",
        impact: "outage",
        message: "Investigating",
        components: ["internal-database"],
      }),
    ).toEqual({ ok: false, error: "unknown component: internal-database" });
    expect(
      validateEventUpdate("maintenance", {
        state: "resolved",
        message: "Wrong terminal state",
      }),
    ).toEqual({ ok: false, error: "invalid maintenance state" });
    expect(
      validateEventUpdate("maintenance", {
        state: "in_progress",
        message: "Bad effective window",
        expectedEndAt: "2026-07-22T00:30:00Z",
      }),
    ).toEqual({
      ok: false,
      error: "maintenance updates must provide both timestamps or neither",
    });
    expect(
      validateCreateEvent({
        kind: "incident",
        title: "Outage",
        impact: "outage",
        message: "Investigating",
        components: ["media"],
        startsAt: "2026-07-22T00:00:00Z",
      }),
    ).toEqual({
      ok: false,
      error: "incident timestamps are not allowed",
    });
  });

  test("rejects unauthenticated mutations before touching D1", async () => {
    const result = await handleRequest(
      new Request("https://status.home.phibkro.org/api/operator/events", {
        method: "POST",
        body: "{}",
      }),
      env,
    );
    expect(result.status).toBe(401);
    expect(result.headers.get("WWW-Authenticate")).toBe("Bearer");
  });

  test("returns 404 for unknown operator routes", async () => {
    const unknown = await handleRequest(
      new Request("https://status.home.phibkro.org/api/operator/typo"),
      env,
    );
    expect(unknown.status).toBe(404);

    const wrongMethod = await handleRequest(
      new Request("https://status.home.phibkro.org/api/operator/events"),
      env,
    );
    expect(wrongMethod.status).toBe(405);
  });
});

describe("external probes", () => {
  const component = components[0]!;

  test("accepts an authentication response as reachable", async () => {
    const result = await probeComponent(
      component,
      async () => new Response(null, { status: 401 }),
      (() => {
        let time = 0;
        return () => (time += 100);
      })(),
    );
    expect(result.state).toBe("operational");
    expect(result.statusCode).toBe(401);
  });

  test("treats an authentication redirect as reachable without following it", async () => {
    let redirect: RequestInit["redirect"];
    const result = await probeComponent(component, async (_input, init) => {
      redirect = init?.redirect;
      return new Response(null, { status: 302 });
    });
    expect(redirect).toBe("manual");
    expect(result.state).toBe("operational");
    expect(result.statusCode).toBe(302);
  });

  test("normalizes network exceptions to outage", async () => {
    const result = await probeComponent(component, async () => {
      throw new Error("secret internal diagnostic");
    });
    expect(result).toMatchObject({
      state: "outage",
      latencyMs: null,
      statusCode: null,
    });
    expect(JSON.stringify(result)).not.toContain("secret internal diagnostic");
  });
});
