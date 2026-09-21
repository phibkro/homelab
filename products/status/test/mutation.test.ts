import { Database, type SQLQueryBindings } from "bun:sqlite";
import { expect, test } from "bun:test";
import type { WorkerEnv } from "../alchemy.run.ts";
import { handleRequest } from "../src/worker.ts";

function sqliteD1(database: Database): D1Database {
  const prepare = (
    sql: string,
    values: SQLQueryBindings[] = [],
  ): D1PreparedStatement => {
    const statement = {
      bind: (...bound: unknown[]) =>
        prepare(sql, bound as SQLQueryBindings[]),
      all: async <T>() => ({ results: database.query(sql).all(...values) as T[] }),
      first: async <T>() =>
        (database.query(sql).get(...values) as T | null) ?? null,
      raw: async <T>() => database.query(sql).values(...values) as T[],
      run: async () => {
        const result = database.query(sql).run(...values);
        return { success: true, meta: { changes: result.changes } };
      },
    };
    return statement as unknown as D1PreparedStatement;
  };
  return {
    prepare,
    batch: async (statements: D1PreparedStatement[]) => {
      const results = [];
      for (const statement of statements) results.push(await statement.run());
      return results;
    },
    dump: async () => new ArrayBuffer(0),
    exec: async () => ({ count: 0, duration: 0 }),
    withSession: () => {
      throw new Error("not implemented in test adapter");
    },
  } as unknown as D1Database;
}

async function migratedDatabase(): Promise<Database> {
  const database = new Database(":memory:");
  for (const name of [
    "0001_component_status.sql",
    "0002_status_events.sql",
  ]) {
    database.exec(
      await Bun.file(new URL(`../migrations/${name}`, import.meta.url)).text(),
    );
  }
  return database;
}

test("authenticated event mutations append public history and cannot reopen terminal events", async () => {
  const database = await migratedDatabase();
  const env = {
    DB: sqliteD1(database),
    MUTATION_TOKEN: "operator-token",
  } as WorkerEnv;
  const create = await handleRequest(
    new Request("https://status.home.phibkro.org/api/operator/events", {
      method: "POST",
      headers: {
        Authorization: "Bearer operator-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        kind: "incident",
        title: "Media unavailable",
        impact: "outage",
        message: "Investigating failed playback",
        components: ["media"],
      }),
    }),
    env,
    new Date("2026-07-22T00:00:00Z"),
  );
  expect(create.status).toBe(201);
  const { id } = (await create.json()) as { id: string };

  const resolve = await handleRequest(
    new Request(
      `https://status.home.phibkro.org/api/operator/events/${id}/updates`,
      {
        method: "POST",
        headers: {
          Authorization: "Bearer operator-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          state: "resolved",
          message: "Playback restored",
        }),
      },
    ),
    env,
    new Date("2026-07-22T00:05:00Z"),
  );
  expect(resolve.status).toBe(201);

  const reopen = await handleRequest(
    new Request(
      `https://status.home.phibkro.org/api/operator/events/${id}/updates`,
      {
        method: "POST",
        headers: { Authorization: "Bearer operator-token" },
        body: JSON.stringify({
          state: "investigating",
          message: "Trying to rewrite terminal history",
        }),
      },
    ),
    env,
  );
  expect(reopen.status).toBe(409);

  const status = await handleRequest(
    new Request("https://status.home.phibkro.org/api/status"),
    env,
    new Date("2026-07-22T00:06:00Z"),
  );
  const body = (await status.json()) as {
    events: Array<{ state: string; updates: unknown[] }>;
  };
  expect(body.events).toHaveLength(1);
  expect(body.events[0]?.state).toBe("resolved");
  expect(body.events[0]?.updates).toHaveLength(2);
  expect(JSON.stringify(body)).not.toContain("operator-token");
  database.close();
});

test("active notices remain public outside the recent-history window", async () => {
  const database = await migratedDatabase();
  database
    .query(
      `INSERT INTO status_events (id, kind, title, impact, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .run(
      "active-maintenance",
      "maintenance",
      "Long maintenance",
      null,
      "2026-07-21T00:00:00Z",
    );
  database
    .query(
      `INSERT INTO status_event_components (event_id, component_id)
       VALUES (?, ?)`,
    )
    .run("active-maintenance", "media");
  database
    .query(
      `INSERT INTO status_event_updates
         (event_id, state, message, starts_at, expected_end_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .run(
      "active-maintenance",
      "in_progress",
      "Work continues",
      "2026-07-21T00:00:00Z",
      "2026-07-23T00:00:00Z",
      "2026-07-21T00:00:00Z",
    );

  const insertEvent = database.query(
    `INSERT INTO status_events (id, kind, title, impact, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  );
  const insertComponent = database.query(
    `INSERT INTO status_event_components (event_id, component_id)
     VALUES (?, ?)`,
  );
  const insertUpdate = database.query(
    `INSERT INTO status_event_updates
       (event_id, state, message, created_at)
     VALUES (?, ?, ?, ?)`,
  );
  for (let index = 0; index < 51; index += 1) {
    const id = `resolved-${index}`;
    const createdAt = new Date(
      Date.UTC(2026, 6, 22, 0, index),
    ).toISOString();
    insertEvent.run(id, "incident", "Resolved incident", "degraded", createdAt);
    insertComponent.run(id, "audio");
    insertUpdate.run(id, "resolved", "Resolved", createdAt);
  }

  const response = await handleRequest(
    new Request("https://status.home.phibkro.org/api/status"),
    {
      DB: sqliteD1(database),
      MUTATION_TOKEN: "operator-token",
    } as WorkerEnv,
    new Date("2026-07-22T01:00:00Z"),
  );
  const body = (await response.json()) as {
    services: Array<{ id: string; state: string }>;
    events: Array<{ id: string; state: string }>;
  };
  expect(body.events).toHaveLength(51);
  expect(body.events.find(({ id }) => id === "active-maintenance")?.state).toBe(
    "in_progress",
  );
  expect(body.services.find(({ id }) => id === "media")?.state).toBe(
    "maintenance",
  );
  database.close();
});
