CREATE TABLE component_status (
  component_id TEXT PRIMARY KEY NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('operational', 'degraded', 'outage')),
  checked_at TEXT NOT NULL,
  latency_ms INTEGER,
  status_code INTEGER
);

CREATE INDEX component_status_checked_at
  ON component_status (checked_at DESC);
