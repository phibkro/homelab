import type { WorkerEnv } from "../alchemy.run.ts";
import {
  components,
  publicStatus,
  renderHtml,
  type StoredComponentStatus,
} from "./status.ts";

const securityHeaders = {
  "Cache-Control": "no-store",
  "Content-Security-Policy":
    "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "X-Robots-Tag": "noindex, nofollow",
} as const;

function response(
  body: BodyInit | null,
  init: ResponseInit & { contentType?: string } = {},
): Response {
  const headers = new Headers(securityHeaders);
  headers.set("Content-Type", init.contentType ?? "text/plain; charset=utf-8");
  return new Response(body, { ...init, headers });
}

async function loadRows(database: D1Database): Promise<StoredComponentStatus[]> {
  const result = await database
    .prepare(
      "SELECT component_id, state, checked_at, latency_ms, status_code FROM component_status",
    )
    .all<StoredComponentStatus>();
  return result.results;
}

export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  now = new Date(),
): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    const denied = response("Method not allowed", { status: 405 });
    denied.headers.set("Allow", "GET, HEAD");
    return denied;
  }

  const path = new URL(request.url).pathname;
  if (path !== "/" && path !== "/api/status") {
    return response("Not found", { status: 404 });
  }

  let rows: StoredComponentStatus[] = [];
  try {
    rows = await loadRows(env.DB);
  } catch {
    // D1 failure is public `unknown`, never a leaked exception or false green.
  }
  const status = publicStatus(rows, now);
  const body =
    path === "/api/status" ? JSON.stringify(status) : renderHtml(status);
  const contentType =
    path === "/api/status"
      ? "application/json; charset=utf-8"
      : "text/html; charset=utf-8";

  return response(request.method === "HEAD" ? null : body, { contentType });
}

type ProbeResult = {
  componentId: string;
  state: "operational" | "degraded" | "outage";
  checkedAt: string;
  latencyMs: number | null;
  statusCode: number | null;
};

type Fetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export async function probeComponent(
  component: (typeof components)[number],
  fetcher: Fetcher = fetch,
  now: () => number = Date.now,
): Promise<ProbeResult> {
  const startedAt = now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);

  try {
    const upstream = await fetcher(component.url, {
      redirect: "follow",
      signal: controller.signal,
      headers: { "User-Agent": "homelab-public-status/1" },
    });
    const latencyMs = Math.max(0, now() - startedAt);
    const reachable =
      (upstream.status >= 200 && upstream.status < 400) ||
      upstream.status === 401 ||
      upstream.status === 403;
    const degraded = upstream.status === 429 || latencyMs > 2_500;

    return {
      componentId: component.id,
      state: reachable ? (degraded ? "degraded" : "operational") : "outage",
      checkedAt: new Date().toISOString(),
      latencyMs,
      statusCode: upstream.status,
    };
  } catch {
    return {
      componentId: component.id,
      state: "outage",
      checkedAt: new Date().toISOString(),
      latencyMs: null,
      statusCode: null,
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function probeAll(database: D1Database): Promise<void> {
  const results = await Promise.all(
    components.map((component) => probeComponent(component)),
  );
  const statements = results.map((result) =>
    database
      .prepare(
        `INSERT INTO component_status
          (component_id, state, checked_at, latency_ms, status_code)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(component_id) DO UPDATE SET
          state = excluded.state,
          checked_at = excluded.checked_at,
          latency_ms = excluded.latency_ms,
          status_code = excluded.status_code`,
      )
      .bind(
        result.componentId,
        result.state,
        result.checkedAt,
        result.latencyMs,
        result.statusCode,
      ),
  );
  await database.batch(statements);
}

export default {
  fetch(request: Request, env: WorkerEnv): Promise<Response> {
    return handleRequest(request, env);
  },
  scheduled(
    _controller: ScheduledController,
    env: WorkerEnv,
    context: ExecutionContext,
  ): void {
    context.waitUntil(probeAll(env.DB));
  },
} satisfies ExportedHandler<WorkerEnv>;
