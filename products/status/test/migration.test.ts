import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";

async function applyMigrations(database: Database): Promise<void> {
  for (const name of [
    "0001_component_status.sql",
    "0002_status_events.sql",
  ]) {
    database.exec(
      await Bun.file(new URL(`../migrations/${name}`, import.meta.url)).text(),
    );
  }
}

test("D1 migrations accept probe state upserts", async () => {
  const database = new Database(":memory:");
  await applyMigrations(database);

  const upsert = database.prepare(`
    INSERT INTO component_status
      (component_id, state, checked_at, latency_ms, status_code)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(component_id) DO UPDATE SET
      state = excluded.state,
      checked_at = excluded.checked_at,
      latency_ms = excluded.latency_ms,
      status_code = excluded.status_code
  `);
  upsert.run("media", "operational", "2026-07-22T00:00:00Z", 42, 200);
  upsert.run("media", "outage", "2026-07-22T00:02:00Z", null, null);

  expect(
    database
      .query("SELECT component_id, state FROM component_status")
      .all(),
  ).toEqual([{ component_id: "media", state: "outage" }]);
  database.close();
});

test("status event history is immutable and terminal", async () => {
  const database = new Database(":memory:");
  await applyMigrations(database);
  database
    .query(
      `INSERT INTO status_events (id, kind, title, impact, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .run("event-1", "incident", "Media unavailable", "outage", "2026-07-22T00:00:00Z");
  database
    .query(
      `INSERT INTO status_event_components (event_id, component_id)
       VALUES (?, ?)`,
    )
    .run("event-1", "media");
  const update = database.query(
    `INSERT INTO status_event_updates (event_id, state, message, created_at)
     VALUES (?, ?, ?, ?)`,
  );
  update.run("event-1", "investigating", "Checking the service", "2026-07-22T00:00:00Z");
  update.run("event-1", "resolved", "Service restored", "2026-07-22T00:05:00Z");
  expect(() =>
    update.run(
      "event-1",
      "monitoring",
      "Trying to reopen",
      "2026-07-22T00:06:00Z",
    ),
  ).toThrow("terminal event cannot be reopened");
  expect(() =>
    database
      .query(
        `UPDATE status_event_updates
         SET message = 'rewritten'
         WHERE event_id = 'event-1'`,
      )
      .run(),
  ).toThrow("status event updates are immutable");
  expect(() =>
    database
      .query("DELETE FROM status_events WHERE id = 'event-1'")
      .run(),
  ).toThrow("status events cannot be deleted");

  database
    .query(
      `INSERT INTO status_events (id, kind, title, impact, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .run(
      "maintenance-1",
      "maintenance",
      "Storage work",
      null,
      "2026-07-22T01:00:00Z",
    );
  expect(() =>
    update.run(
      "maintenance-1",
      "investigating",
      "Wrong state family",
      "2026-07-22T01:00:00Z",
    ),
  ).toThrow("event update state does not match event kind");
  expect(() =>
    database
      .query(
        `INSERT INTO status_event_updates
           (event_id, state, message, starts_at, expected_end_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(
        "maintenance-1",
        "in_progress",
        "Invalid window",
        "2026-07-22T02:00:00Z",
        null,
        "2026-07-22T01:00:00Z",
      ),
  ).toThrow("event update state does not match event kind");

  expect(
    database
      .query(
        `SELECT state, message
         FROM status_event_updates
         WHERE event_id = ?
         ORDER BY sequence`,
      )
      .all("event-1"),
  ).toEqual([
    { state: "investigating", message: "Checking the service" },
    { state: "resolved", message: "Service restored" },
  ]);
  database.close();
});
