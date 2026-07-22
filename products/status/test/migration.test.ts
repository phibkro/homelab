import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";

test("D1 migration accepts probe state upserts", async () => {
  const database = new Database(":memory:");
  const migration = await Bun.file(
    new URL("../migrations/0001_component_status.sql", import.meta.url),
  ).text();
  database.exec(migration);

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
