import { components } from "./status.ts";

export const incidentStates = [
  "investigating",
  "identified",
  "monitoring",
  "resolved",
] as const;
export const maintenanceStates = [
  "scheduled",
  "in_progress",
  "completed",
] as const;

export type EventKind = "incident" | "maintenance";
export type IncidentState = (typeof incidentStates)[number];
export type MaintenanceState = (typeof maintenanceStates)[number];
export type EventState = IncidentState | MaintenanceState;
export type IncidentImpact = "degraded" | "outage";

export type CreateEvent = {
  kind: EventKind;
  title: string;
  impact: IncidentImpact | null;
  components: string[];
  state: EventState;
  message: string;
  startsAt: string | null;
  expectedEndAt: string | null;
};

export type AppendEventUpdate = {
  state: EventState;
  message: string;
  startsAt: string | null;
  expectedEndAt: string | null;
};

export function transitionAllowed(
  kind: EventKind,
  current: EventState,
  next: EventState,
): boolean {
  if (current === "resolved" || current === "completed") return false;
  if (kind === "incident") return incidentStates.includes(next as IncidentState);
  if (!maintenanceStates.includes(next as MaintenanceState)) return false;
  if (current === "scheduled") {
    return next === "scheduled" || next === "in_progress" || next === "completed";
  }
  return (
    current === "in_progress" &&
    (next === "in_progress" || next === "completed")
  );
}

type ValidationResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

const componentIds = new Set(components.map(({ id }) => id));

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function boundedString(
  value: unknown,
  field: string,
  maximum: number,
): ValidationResult<string> {
  if (typeof value !== "string" || value.trim() === "") {
    return { ok: false, error: `${field} must be a non-empty string` };
  }
  const normalized = value.trim();
  return normalized.length <= maximum
    ? { ok: true, value: normalized }
    : { ok: false, error: `${field} must be at most ${maximum} characters` };
}

function optionalTimestamp(
  value: unknown,
  field: string,
): ValidationResult<string | null> {
  if (value === undefined || value === null) return { ok: true, value: null };
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    return { ok: false, error: `${field} must be an ISO-8601 timestamp` };
  }
  return { ok: true, value: new Date(value).toISOString() };
}

function componentsValue(value: unknown): ValidationResult<string[]> {
  if (!Array.isArray(value) || value.length === 0) {
    return { ok: false, error: "components must be a non-empty array" };
  }
  if (!value.every((item) => typeof item === "string")) {
    return { ok: false, error: "components must contain only strings" };
  }
  const normalized = [...new Set(value)];
  const unknown = normalized.filter((id) => !componentIds.has(id));
  return unknown.length === 0
    ? { ok: true, value: normalized }
    : { ok: false, error: `unknown component: ${unknown.join(", ")}` };
}

function timestampsValue(
  input: Record<string, unknown>,
): ValidationResult<{ startsAt: string | null; expectedEndAt: string | null }> {
  const startsAt = optionalTimestamp(input.startsAt, "startsAt");
  if (!startsAt.ok) return startsAt;
  const expectedEndAt = optionalTimestamp(
    input.expectedEndAt,
    "expectedEndAt",
  );
  if (!expectedEndAt.ok) return expectedEndAt;
  if (
    startsAt.value !== null &&
    expectedEndAt.value !== null &&
    Date.parse(expectedEndAt.value) <= Date.parse(startsAt.value)
  ) {
    return { ok: false, error: "expectedEndAt must be after startsAt" };
  }
  return {
    ok: true,
    value: { startsAt: startsAt.value, expectedEndAt: expectedEndAt.value },
  };
}

export function validateCreateEvent(
  value: unknown,
): ValidationResult<CreateEvent> {
  const input = objectValue(value);
  if (input === null) return { ok: false, error: "body must be an object" };
  if (input.kind !== "incident" && input.kind !== "maintenance") {
    return { ok: false, error: "kind must be incident or maintenance" };
  }
  const title = boundedString(input.title, "title", 120);
  if (!title.ok) return title;
  const message = boundedString(input.message, "message", 1000);
  if (!message.ok) return message;
  const affected = componentsValue(input.components);
  if (!affected.ok) return affected;
  const timestamps = timestampsValue(input);
  if (!timestamps.ok) return timestamps;

  if (input.kind === "incident") {
    if (input.impact !== "degraded" && input.impact !== "outage") {
      return { ok: false, error: "incident impact must be degraded or outage" };
    }
    if (
      timestamps.value.startsAt !== null ||
      timestamps.value.expectedEndAt !== null
    ) {
      return { ok: false, error: "incident timestamps are not allowed" };
    }
    const state = input.state ?? "investigating";
    if (!incidentStates.includes(state as IncidentState)) {
      return { ok: false, error: "invalid incident state" };
    }
    return {
      ok: true,
      value: {
        kind: "incident",
        title: title.value,
        impact: input.impact,
        components: affected.value,
        state: state as IncidentState,
        message: message.value,
        ...timestamps.value,
      },
    };
  }

  const state = input.state ?? "in_progress";
  if (!maintenanceStates.includes(state as MaintenanceState)) {
    return { ok: false, error: "invalid maintenance state" };
  }
  if (
    timestamps.value.startsAt === null ||
    timestamps.value.expectedEndAt === null
  ) {
    return {
      ok: false,
      error: "maintenance requires startsAt and expectedEndAt",
    };
  }
  return {
    ok: true,
    value: {
      kind: "maintenance",
      title: title.value,
      impact: null,
      components: affected.value,
      state: state as MaintenanceState,
      message: message.value,
      ...timestamps.value,
    },
  };
}

export function validateEventUpdate(
  kind: EventKind,
  value: unknown,
): ValidationResult<AppendEventUpdate> {
  const input = objectValue(value);
  if (input === null) return { ok: false, error: "body must be an object" };
  const message = boundedString(input.message, "message", 1000);
  if (!message.ok) return message;
  const timestamps = timestampsValue(input);
  if (!timestamps.ok) return timestamps;
  if (
    kind === "incident" &&
    (timestamps.value.startsAt !== null ||
      timestamps.value.expectedEndAt !== null)
  ) {
    return { ok: false, error: "incident timestamps are not allowed" };
  }
  if (
    kind === "maintenance" &&
    (timestamps.value.startsAt === null) !==
      (timestamps.value.expectedEndAt === null)
  ) {
    return {
      ok: false,
      error: "maintenance updates must provide both timestamps or neither",
    };
  }
  const states = kind === "incident" ? incidentStates : maintenanceStates;
  if (!states.includes(input.state as never)) {
    return { ok: false, error: `invalid ${kind} state` };
  }
  return {
    ok: true,
    value: {
      state: input.state as EventState,
      message: message.value,
      ...timestamps.value,
    },
  };
}

async function digest(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

export async function hasValidBearerToken(
  request: Request,
  expectedToken: string,
): Promise<boolean> {
  const authorization = request.headers.get("Authorization");
  const supplied = authorization?.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : "";
  const [actualDigest, expectedDigest] = await Promise.all([
    digest(supplied),
    digest(expectedToken),
  ]);
  let difference = supplied.length === 0 || expectedToken.length === 0 ? 1 : 0;
  for (let index = 0; index < actualDigest.length; index += 1) {
    difference |= actualDigest[index]! ^ expectedDigest[index]!;
  }
  return difference === 0;
}

export async function parseJsonBody(request: Request): Promise<unknown> {
  const body = await request.text();
  if (new TextEncoder().encode(body).byteLength > 8_192) {
    throw new Error("request body exceeds 8192 bytes");
  }
  try {
    return JSON.parse(body) as unknown;
  } catch {
    throw new Error("request body must be valid JSON");
  }
}
