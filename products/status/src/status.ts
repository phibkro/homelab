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

export type PublicComponentStatus = Component & {
  state: ComponentState;
  checkedAt: string | null;
};

export type PublicStatus = {
  version: 1;
  generatedAt: string;
  overall: ComponentState;
  services: PublicComponentStatus[];
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
): PublicStatus {
  const byId = new Map(rows.map((row) => [row.component_id, row]));
  const services = components.map((component): PublicComponentStatus => {
    const row = byId.get(component.id);
    return {
      ...component,
      state: row?.state ?? "unknown",
      checkedAt: row?.checked_at ?? null,
    };
  });

  return {
    version: 1,
    generatedAt: now.toISOString(),
    overall: overallState(services),
    services,
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
      .service { display: grid; grid-template-columns: 1rem 1fr auto; gap: 1rem; align-items: center; padding: 1.2rem; margin: .75rem 0; border: 1px solid #263a53; border-radius: 1rem; background: rgba(13, 27, 45, .86); }
      .service h2, .service p { margin: 0; }
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
      <section aria-label="Services">${services}</section>
      <footer>Updated <time datetime="${escapeHtml(status.generatedAt)}">${escapeHtml(status.generatedAt)}</time></footer>
    </main>
  </body>
</html>`;
}
