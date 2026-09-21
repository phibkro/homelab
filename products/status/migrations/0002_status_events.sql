CREATE TABLE status_events (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('incident', 'maintenance')),
  title TEXT NOT NULL,
  impact TEXT CHECK (impact IN ('degraded', 'outage')),
  created_at TEXT NOT NULL,
  CHECK (
    (kind = 'incident' AND impact IS NOT NULL)
    OR (kind = 'maintenance' AND impact IS NULL)
  )
);

CREATE TABLE status_event_components (
  event_id TEXT NOT NULL REFERENCES status_events(id),
  component_id TEXT NOT NULL,
  PRIMARY KEY (event_id, component_id)
);

CREATE TABLE status_event_updates (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL REFERENCES status_events(id),
  state TEXT NOT NULL CHECK (
    state IN (
      'investigating',
      'identified',
      'monitoring',
      'resolved',
      'scheduled',
      'in_progress',
      'completed'
    )
  ),
  message TEXT NOT NULL,
  starts_at TEXT,
  expected_end_at TEXT,
  created_at TEXT NOT NULL
);
CREATE TRIGGER status_event_updates_kind_guard
BEFORE INSERT ON status_event_updates
WHEN NOT EXISTS (
  SELECT 1
  FROM status_events
  WHERE id = NEW.event_id
    AND (
      (
        kind = 'incident'
        AND NEW.state IN ('investigating', 'identified', 'monitoring', 'resolved')
        AND NEW.starts_at IS NULL
        AND NEW.expected_end_at IS NULL
      )
      OR (
        kind = 'maintenance'
        AND NEW.state IN ('scheduled', 'in_progress', 'completed')
        AND (
          (NEW.starts_at IS NULL AND NEW.expected_end_at IS NULL)
          OR (
            unixepoch(NEW.starts_at) IS NOT NULL
            AND unixepoch(NEW.expected_end_at) IS NOT NULL
            AND unixepoch(NEW.expected_end_at) > unixepoch(NEW.starts_at)
          )
        )
      )
    )
)
BEGIN
  SELECT RAISE(ABORT, 'event update state does not match event kind');
END;

CREATE TRIGGER status_event_updates_terminal_guard
BEFORE INSERT ON status_event_updates
WHEN EXISTS (
  SELECT 1
  FROM status_event_updates
  WHERE event_id = NEW.event_id
    AND state IN ('resolved', 'completed')
)
BEGIN
  SELECT RAISE(ABORT, 'terminal event cannot be reopened');
END;

CREATE TRIGGER status_events_immutable
BEFORE UPDATE ON status_events
BEGIN
  SELECT RAISE(ABORT, 'status events are immutable');
END;

CREATE TRIGGER status_events_no_delete
BEFORE DELETE ON status_events
BEGIN
  SELECT RAISE(ABORT, 'status events cannot be deleted');
END;

CREATE TRIGGER status_event_components_immutable
BEFORE UPDATE ON status_event_components
BEGIN
  SELECT RAISE(ABORT, 'status event components are immutable');
END;

CREATE TRIGGER status_event_components_no_delete
BEFORE DELETE ON status_event_components
BEGIN
  SELECT RAISE(ABORT, 'status event components cannot be deleted');
END;

CREATE TRIGGER status_event_updates_immutable
BEFORE UPDATE ON status_event_updates
BEGIN
  SELECT RAISE(ABORT, 'status event updates are immutable');
END;

CREATE TRIGGER status_event_updates_no_delete
BEFORE DELETE ON status_event_updates
BEGIN
  SELECT RAISE(ABORT, 'status event updates cannot be deleted');
END;
CREATE INDEX status_events_created
  ON status_events (created_at DESC, id DESC);


CREATE INDEX status_event_updates_event_sequence
  ON status_event_updates (event_id, sequence DESC);

CREATE INDEX status_event_updates_created_at
  ON status_event_updates (created_at DESC);
