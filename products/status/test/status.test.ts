import { describe, expect, test } from "bun:test";
import {
  components,
  escapeHtml,
  overallState,
  publicStatus,
  renderHtml,
  type StoredComponentStatus,
} from "../src/status.ts";
import { handleRequest, probeComponent } from "../src/worker.ts";
import type { WorkerEnv } from "../alchemy.run.ts";

const emptyDatabase = {
  prepare: () => ({
    all: async () => ({ results: [] }),
  }),
} as unknown as D1Database;
const env = { DB: emptyDatabase } as WorkerEnv;

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
      version: 1,
      generatedAt: `"><script>bad()</script>`,
      overall: "unknown",
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
