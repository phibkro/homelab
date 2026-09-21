import componentCatalog from "../generated/components.json";

export const componentStates = [
  "operational",
  "degraded",
  "maintenance",
  "outage",
  "unknown",
] as const;

export type ComponentState = (typeof componentStates)[number];

export type Component = {
  id: string;
  title: string;
  description: string;
  url: string;
};

export type StoredComponentStatus = {
  component_id: string;
  state: "operational" | "degraded" | "outage";
  checked_at: string;
  latency_ms: number | null;
  status_code: number | null;
};

export type StoredEvent = {
  id: string;
  kind: "incident" | "maintenance";
  title: string;
  impact: "degraded" | "outage" | null;
  created_at: string;
};

export type StoredEventUpdate = {
  event_id: string;
  sequence: number;
  state:
    | "investigating"
    | "identified"
    | "monitoring"
    | "resolved"
    | "scheduled"
    | "in_progress"
    | "completed";
  message: string;
  starts_at: string | null;
  expected_end_at: string | null;
  created_at: string;
};

export type StoredEventComponent = {
  event_id: string;
  component_id: string;
};

export type PublicComponentStatus = Component & {
  state: ComponentState;
  checkedAt: string | null;
};

export type PublicEvent = {
  id: string;
  kind: "incident" | "maintenance";
  title: string;
  state: StoredEventUpdate["state"];
  impact: "degraded" | "outage" | null;
  message: string;
  components: string[];
  createdAt: string;
  updatedAt: string;
  startsAt: string | null;
  expectedEndAt: string | null;
  updates: Array<{
    state: StoredEventUpdate["state"];
    message: string;
    createdAt: string;
  }>;
};

export type PublicStatus = {
  version: 2;
  generatedAt: string;
  overall: ComponentState;
  services: PublicComponentStatus[];
  events: PublicEvent[];
};

type Catalog = {
  services: Record<string, Omit<Component, "id">>;
};

export const components: Component[] = Object.entries(
  (componentCatalog as Catalog).services,
).map(([id, component]) => ({ id, ...component }));

export function overallState(
  services: ReadonlyArray<Pick<PublicComponentStatus, "state">>,
): ComponentState {
  const states = new Set(services.map((service) => service.state));
  if (states.has("outage")) return "outage";
  if (states.has("maintenance")) return "maintenance";
  if (states.has("degraded")) return "degraded";
  if (states.has("unknown")) return "unknown";
  return "operational";
}

export function publicStatus(
  rows: ReadonlyArray<StoredComponentStatus>,
  now = new Date(),
  eventRows: ReadonlyArray<StoredEvent> = [],
  eventComponents: ReadonlyArray<StoredEventComponent> = [],
  eventUpdateRows: ReadonlyArray<StoredEventUpdate> = [],
): PublicStatus {
  const byId = new Map(rows.map((row) => [row.component_id, row]));
  const publishedComponentIds = new Set(components.map(({ id }) => id));
  const componentsByEvent = new Map<string, string[]>();
  for (const mapping of eventComponents) {
    if (!publishedComponentIds.has(mapping.component_id)) continue;
    const current = componentsByEvent.get(mapping.event_id) ?? [];
    componentsByEvent.set(mapping.event_id, [...current, mapping.component_id]);
  }
  const updatesByEvent = new Map<string, StoredEventUpdate[]>();
  for (const update of eventUpdateRows) {
    const current = updatesByEvent.get(update.event_id) ?? [];
    updatesByEvent.set(update.event_id, [...current, update]);
  }
  const events = eventRows.flatMap((event): PublicEvent[] => {
    const updates = updatesByEvent.get(event.id) ?? [];
    const latest = updates.at(-1);
    if (latest === undefined) return [];
    const latestStartsAt =
      [...updates]
        .reverse()
        .find(({ starts_at }) => starts_at !== null)?.starts_at ?? null;
    const latestExpectedEndAt =
      [...updates]
        .reverse()
        .find(({ expected_end_at }) => expected_end_at !== null)
        ?.expected_end_at ?? null;
    return [
      {
        id: event.id,
        kind: event.kind,
        title: event.title,
        state: latest.state,
        impact: event.impact,
        message: latest.message,
        components: componentsByEvent.get(event.id) ?? [],
        createdAt: event.created_at,
        updatedAt: latest.created_at,
        startsAt: latestStartsAt,
        expectedEndAt: latestExpectedEndAt,
        updates: updates.map((update) => ({
          state: update.state,
          message: update.message,
          createdAt: update.created_at,
        })),
      },
    ];
  });
  const overrideFor = (componentId: string): ComponentState | null => {
    const states = events.flatMap((event): ComponentState[] => {
      if (!event.components.includes(componentId)) return [];
      if (event.kind === "incident" && event.state !== "resolved") {
        return [event.impact ?? "degraded"];
      }
      const started =
        event.startsAt !== null && Date.parse(event.startsAt) <= now.getTime();
      if (
        event.kind === "maintenance" &&
        event.state !== "completed" &&
        (event.state === "in_progress" || started)
      ) {
        return ["maintenance"];
      }
      return [];
    });
    if (states.includes("outage")) return "outage";
    if (states.includes("maintenance")) return "maintenance";
    if (states.includes("degraded")) return "degraded";
    return null;
  };
  const services = components.map((component): PublicComponentStatus => {
    const row = byId.get(component.id);
    return {
      ...component,
      state: overrideFor(component.id) ?? row?.state ?? "unknown",
      checkedAt: row?.checked_at ?? null,
    };
  });

  return {
    version: 2,
    generatedAt: now.toISOString(),
    overall: overallState(services),
    services,
    events,
  };
}

export function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character] ?? character,
  );
}

export function renderHtml(status: PublicStatus): string {
  const events = status.events
    .map(
      (event) => `
        <article class="notice ${event.kind}">
          <div>
            <span>${escapeHtml(event.kind)}</span>
            <h2>${escapeHtml(event.title)}</h2>
            <ol>${event.updates
              .map(
                (update) =>
                  `<li><time datetime="${escapeHtml(update.createdAt)}">${escapeHtml(update.createdAt)}</time> — ${escapeHtml(update.message)}</li>`,
              )
              .join("")}</ol>
          </div>
          <strong>${escapeHtml(event.state.replace("_", " "))}</strong>
        </article>`,
    )
    .join("");
  const services = status.services
    .map(
      (service) => `
        <article class="service">
          <span class="dot ${service.state}" aria-hidden="true"></span>
          <div>
            <h2><a href="${escapeHtml(service.url)}">${escapeHtml(service.title)}</a></h2>
            <p>${escapeHtml(service.description)}</p>
          </div>
          <strong>${escapeHtml(service.state)}</strong>
        </article>`,
    )
    .join("");

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="dark light">
    <title>Homelab service status</title>
    <style>
      :root { color-scheme: dark; font-family: ui-sans-serif, system-ui, sans-serif; background: #08111f; color: #e6edf7; }
      body { margin: 0; min-height: 100vh; background: radial-gradient(circle at top, #162a46, #08111f 55%); }
      main { width: min(44rem, calc(100% - 2rem)); margin: 0 auto; padding: 4rem 0; }
      header { margin-bottom: 2rem; }
      h1 { margin: 0 0 .5rem; font-size: clamp(2rem, 8vw, 3.75rem); letter-spacing: -.045em; }
      header p, .service p, footer { color: #9eb0c8; }
      .summary { display: inline-flex; gap: .6rem; align-items: center; margin-top: 1rem; padding: .55rem .8rem; border: 1px solid #31455f; border-radius: 999px; background: #101d2f; }
      .service, .notice { display: grid; grid-template-columns: 1rem 1fr auto; gap: 1rem; align-items: center; padding: 1.2rem; margin: .75rem 0; border: 1px solid #263a53; border-radius: 1rem; background: rgba(13, 27, 45, .86); }
      .notice { grid-template-columns: 1fr auto; border-color: #735c27; }
      .notice span { color: #f7c75d; font-size: .72rem; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
      .notice ol { margin: .75rem 0 0; padding-left: 1.25rem; color: #9eb0c8; font-size: .82rem; }
      .service h2, .service p, .notice h2, .notice p { margin: 0; }
      .service h2 { font-size: 1.05rem; }
      .service a { color: inherit; text-decoration-color: #536d8b; text-underline-offset: .2em; }
      .service p { margin-top: .25rem; font-size: .9rem; }
      .service strong { font-size: .78rem; text-transform: uppercase; letter-spacing: .08em; }
      .dot { width: .75rem; height: .75rem; border-radius: 50%; background: #7d8da3; box-shadow: 0 0 .75rem currentColor; }
      .operational { color: #5ee49a; background: #5ee49a; }
      .degraded, .maintenance { color: #f7c75d; background: #f7c75d; }
      .outage { color: #ff6b79; background: #ff6b79; }
      .unknown { color: #8fa2bb; background: #8fa2bb; }
      footer { margin-top: 2rem; font-size: .8rem; }
    </style>
  </head>
  <body>
    <main>
      <header>
        <h1>Service status</h1>
        <p>Availability for family-facing homelab services.</p>
        <div class="summary"><span class="dot ${status.overall}" aria-hidden="true"></span><strong>${escapeHtml(status.overall)}</strong></div>
      </header>
      ${events === "" ? "" : `<section aria-label="Incidents and maintenance"><h2>Notices</h2>${events}</section>`}
      <section aria-label="Services">${services}</section>
      <footer>Updated <time datetime="${escapeHtml(status.generatedAt)}">${escapeHtml(status.generatedAt)}</time></footer>
    </main>
  </body>
</html>`;
}
