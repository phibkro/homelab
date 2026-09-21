import type { WorkerEnv } from "../alchemy.run.ts";
import {
  components,
  publicStatus,
  renderHtml,
  type StoredComponentStatus,
  type StoredEvent,
  type StoredEventComponent,
  type StoredEventUpdate,
} from "./status.ts";
import {
  hasValidBearerToken,
  parseJsonBody,
  validateCreateEvent,
  validateEventUpdate,
  transitionAllowed,
  type AppendEventUpdate,
  type CreateEvent,
  type EventKind,
} from "./operator.ts";

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

async function loadEvents(database: D1Database): Promise<{
  events: StoredEvent[];
  components: StoredEventComponent[];
  updates: StoredEventUpdate[];
}> {
  const eventRows = await database
    .prepare(
      `WITH active_events AS (
         SELECT event.id, event.kind, event.title, event.impact, event.created_at
         FROM status_events AS event
         WHERE (
           SELECT update_row.state
           FROM status_event_updates AS update_row
           WHERE update_row.event_id = event.id
           ORDER BY update_row.sequence DESC
           LIMIT 1
         ) NOT IN ('resolved', 'completed')
       ),
       recent_events AS (
         SELECT event.id, event.kind, event.title, event.impact, event.created_at
         FROM status_events AS event
         ORDER BY event.created_at DESC, event.id DESC
         LIMIT 50
       )
       SELECT * FROM active_events
       UNION
       SELECT * FROM recent_events
       ORDER BY created_at DESC, id DESC`,
    )
    .all<StoredEvent>();
  const eventIds = eventRows.results.map(({ id }) => id);
  if (eventIds.length === 0) {
    return { events: [], components: [], updates: [] };
  }

  const placeholders = eventIds.map(() => "?").join(", ");
  const [eventComponents, eventUpdates] = await Promise.all([
    database
      .prepare(
        `SELECT event_id, component_id
         FROM status_event_components
         WHERE event_id IN (${placeholders})
         ORDER BY event_id, component_id`,
      )
      .bind(...eventIds)
      .all<StoredEventComponent>(),
    database
      .prepare(
        `SELECT sequence, event_id, state, message, starts_at,
                expected_end_at, created_at
         FROM status_event_updates
         WHERE event_id IN (${placeholders})
         ORDER BY event_id, sequence`,
      )
      .bind(...eventIds)
      .all<StoredEventUpdate>(),
  ]);
  return {
    events: eventRows.results,
    components: eventComponents.results,
    updates: eventUpdates.results,
  };
}

function jsonResponse(value: unknown, status = 200): Response {
  return response(JSON.stringify(value), {
    status,
    contentType: "application/json; charset=utf-8",
  });
}

async function createEvent(
  database: D1Database,
  event: CreateEvent,
  now: Date,
): Promise<string> {
  const id = crypto.randomUUID();
  const createdAt = now.toISOString();
  await database.batch([
    database
      .prepare(
        `INSERT INTO status_events (id, kind, title, impact, created_at)
         VALUES (?, ?, ?, ?, ?)`,
      )
      .bind(id, event.kind, event.title, event.impact, createdAt),
    ...event.components.map((componentId) =>
      database
        .prepare(
          `INSERT INTO status_event_components (event_id, component_id)
           VALUES (?, ?)`,
        )
        .bind(id, componentId),
    ),
    database
      .prepare(
        `INSERT INTO status_event_updates
           (event_id, state, message, starts_at, expected_end_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        id,
        event.state,
        event.message,
        event.startsAt,
        event.expectedEndAt,
        createdAt,
      ),
  ]);
  return id;
}

async function appendEventUpdate(
  database: D1Database,
  id: string,
  current: { sequence: number; state: AppendEventUpdate["state"] },
  update: AppendEventUpdate,
  now: Date,
): Promise<boolean> {
  const result = await database
    .prepare(
      `INSERT INTO status_event_updates
         (event_id, state, message, starts_at, expected_end_at, created_at)
       SELECT ?, ?, ?, ?, ?, ?
       WHERE (
         SELECT sequence FROM status_event_updates
         WHERE event_id = ? ORDER BY sequence DESC LIMIT 1
       ) = ?
       AND (
         SELECT state FROM status_event_updates
         WHERE event_id = ? ORDER BY sequence DESC LIMIT 1
       ) = ?`,
    )
    .bind(
      id,
      update.state,
      update.message,
      update.startsAt,
      update.expectedEndAt,
      now.toISOString(),
      id,
      current.sequence,
      id,
      current.state,
    )
    .run();
  return result.meta.changes === 1;
}

async function currentEvent(
  database: D1Database,
  id: string,
): Promise<{
  kind: EventKind;
  sequence: number;
  state: AppendEventUpdate["state"];
} | null> {
  const event = await database
    .prepare(
      `SELECT event.kind, update_row.sequence, update_row.state
       FROM status_events AS event
       JOIN status_event_updates AS update_row
         ON update_row.sequence = (
           SELECT sequence FROM status_event_updates
           WHERE event_id = event.id ORDER BY sequence DESC LIMIT 1
         )
       WHERE event.id = ?`,
    )
    .bind(id)
    .first<{
      kind: EventKind;
      sequence: number;
      state: AppendEventUpdate["state"];
    }>();
  return event ?? null;
}

async function handleOperatorRequest(
  request: Request,
  env: WorkerEnv,
  path: string,
  now: Date,
): Promise<Response> {
  const updateMatch = path.match(
    /^\/api\/operator\/events\/([^/]+)\/updates$/,
  );
  if (path !== "/api/operator/events" && updateMatch === null) {
    return response("Not found", { status: 404 });
  }
  if (request.method !== "POST") {
    const denied = response("Method not allowed", { status: 405 });
    denied.headers.set("Allow", "POST");
    return denied;
  }
  if (!(await hasValidBearerToken(request, env.MUTATION_TOKEN))) {
    const denied = response("Unauthorized", { status: 401 });
    denied.headers.set("WWW-Authenticate", "Bearer");
    return denied;
  }

  let body: unknown;
  try {
    body = await parseJsonBody(request);
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "invalid request" },
      400,
    );
  }

  try {
    if (path === "/api/operator/events") {
      const event = validateCreateEvent(body);
      if (!event.ok) return jsonResponse({ error: event.error }, 400);
      const id = await createEvent(env.DB, event.value, now);
      return jsonResponse({ id }, 201);
    }

    const id = decodeURIComponent(updateMatch![1]!);
    const event = await currentEvent(env.DB, id);
    if (event === null) return response("Not found", { status: 404 });
    const update = validateEventUpdate(event.kind, body);
    if (!update.ok) return jsonResponse({ error: update.error }, 400);
    if (!transitionAllowed(event.kind, event.state, update.value.state)) {
      return jsonResponse(
        { error: "event is terminal or transition is invalid" },
        409,
      );
    }
    if (!(await appendEventUpdate(env.DB, id, event, update.value, now))) {
      return jsonResponse({ error: "event changed concurrently" }, 409);
    }
    return jsonResponse({ id }, 201);
  } catch {
    return jsonResponse({ error: "status history unavailable" }, 503);
  }
}

export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  now = new Date(),
): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (path.startsWith("/api/operator/")) {
    return handleOperatorRequest(request, env, path, now);
  }

  if (path !== "/" && path !== "/api/status") {
    return response("Not found", { status: 404 });
  }

  if (request.method !== "GET" && request.method !== "HEAD") {
    const denied = response("Method not allowed", { status: 405 });
    denied.headers.set("Allow", "GET, HEAD");
    return denied;
  }

  let rows: StoredComponentStatus[] = [];
  let events: StoredEvent[] = [];
  let eventComponents: StoredEventComponent[] = [];
  let eventUpdates: StoredEventUpdate[] = [];
  try {
    rows = await loadRows(env.DB);
  } catch {
    // D1 failure is public `unknown`, never a leaked exception or false green.
  }
  try {
    ({ events, components: eventComponents, updates: eventUpdates } =
      await loadEvents(env.DB));
  } catch {
    // Event-history failure must not erase otherwise healthy probe results.
  }
  const status = publicStatus(rows, now, events, eventComponents, eventUpdates);
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
  ): Promise<void> {
    return probeAll(env.DB);
  },
} satisfies ExportedHandler<WorkerEnv>;
