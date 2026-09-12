/* runtime-adapter: installed CLI bridge using Bun.fetch over the local Unix socket. */
import { Effect, Schema } from "effect";
import {
  DesktopSettingsError,
  assertNonNegativeSafeInteger,
  parseJson,
  type ApplyRequest,
  type ChangeRequest,
} from "./contracts.ts";

export type CliRuntime = {
  readonly socket: string;
};

function runtimeFromEnvironment(): CliRuntime {
  const configured = process.env.NORI_DESKTOP_SETTINGS_SOCKET;
  if (configured !== undefined && configured.length > 0) return { socket: configured };
  const runtimeDirectory = process.env.XDG_RUNTIME_DIR;
  if (runtimeDirectory === undefined || runtimeDirectory.length === 0) {
    throw new DesktopSettingsError("unavailable", "XDG_RUNTIME_DIR is not configured");
  }
  return { socket: `${runtimeDirectory}/nori-desktop/settings.sock` };
}

async function decodeResponse(text: string): Promise<Record<string, unknown>> {
  const decoded = await Effect.runPromise(parseJson(Schema.Unknown, text, "IPC response"));
  if (typeof decoded !== "object" || decoded === null || Array.isArray(decoded)) {
    throw new DesktopSettingsError("unavailable", "Settings service returned a non-object response");
  }
  return decoded as Record<string, unknown>;
}

function serviceError(response: Record<string, unknown>): DesktopSettingsError {
  const value = response.error;
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return new DesktopSettingsError("unavailable", "Settings service returned an invalid failure response");
  }
  const error = value as Record<string, unknown>;
  const code = typeof error.code === "string" ? error.code : "unavailable";
  const message = typeof error.message === "string" ? error.message : "Settings service rejected request";
  const known = [
    "activation_rejected",
    "invalid_profile",
    "invalid_request",
    "job_failed",
    "not_found",
    "revision_conflict",
    "runtime_unavailable",
    "unknown_setting",
    "unavailable",
  ] as const;
  const matched = known.find((candidate) => candidate === code);
  return new DesktopSettingsError(matched ?? "unavailable", message, error.details);
}

export async function callService(
  path: string,
  method: "GET" | "POST",
  payload?: unknown,
  runtime = runtimeFromEnvironment(),
): Promise<Record<string, unknown>> {
  let response: Response;
  try {
    const init: BunFetchRequestInit = {
      unix: runtime.socket,
      method,
      ...(payload === undefined
        ? {}
        : { headers: { "content-type": "application/json" }, body: JSON.stringify(payload) }),
    };
    response = await fetch(`http://localhost${path}`, init);
  } catch (cause) {
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot contact nori-desktop-config: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  const decoded = await decodeResponse(await response.text());
  if (decoded.ok === true) return decoded;
  throw serviceError(decoded);
}

function parseRevision(value: string | undefined): number {
  if (value === undefined || !/^(0|[1-9][0-9]*)$/.test(value)) {
    throw new DesktopSettingsError("invalid_request", "--expected-revision requires a non-negative integer");
  }
  const revision = Number(value);
  if (!Number.isSafeInteger(revision)) {
    throw new DesktopSettingsError("invalid_request", "--expected-revision exceeds the safe integer range");
  }
  return revision;
}

const ProfileRevision = Schema.Struct({ revision: Schema.Number });

async function savedCommandRevision(): Promise<number> {
  const response = await callService("/v1/saved-commands", "GET");
  const profile = await Effect.runPromise(
    Schema.decodeUnknownEffect(ProfileRevision)(response.profile).pipe(
      Effect.mapError((error) => new DesktopSettingsError("unavailable", `Invalid profile response: ${error}`)),
    ),
  );
  assertNonNegativeSafeInteger(profile.revision, "Profile revision");
  return profile.revision;
}

async function parseValue(value: string): Promise<unknown> {
  return Effect.runPromise(parseJson(Schema.Unknown, value, "setting JSON value"));
}

function writeJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function failure(cause: unknown): void {
  const error =
    cause instanceof DesktopSettingsError
      ? cause
      : new DesktopSettingsError("unavailable", cause instanceof Error ? cause.message : String(cause));
  const body =
    error.details === undefined
      ? { ok: false, error: { code: error.code, message: error.message } }
      : { ok: false, error: { code: error.code, message: error.message, details: error.details } };
  writeJson(body);
}

function commandUsage(): never {
  throw new DesktopSettingsError(
    "invalid_request",
    "usage: nori-desktop-settings {state|preview|change|apply|saved-command} --json",
  );
}

export async function runSettingsCli(args: ReadonlyArray<string>): Promise<number> {
  try {
    const [operation, ...rest] = args;
    if (operation === "state" && rest.length === 1 && rest[0] === "--json") {
      writeJson(await callService("/v1/state", "GET"));
      return 0;
    }
    if (operation === "change" || operation === "preview") {
      const [component, setting, value, revisionFlag, revision, jsonFlag] = rest;
      if (
        component === undefined ||
        setting === undefined ||
        value === undefined ||
        revisionFlag !== "--expected-revision" ||
        jsonFlag !== "--json" ||
        rest.length !== 6
      ) {
        commandUsage();
      }
      const payload: ChangeRequest = {
        component,
        setting,
        value: await parseValue(value),
        expectedRevision: parseRevision(revision),
      };
      writeJson(await callService(operation === "change" ? "/v1/change" : "/v1/preview", "POST", payload));
      return 0;
    }
    if (operation === "apply") {
      const [revisionFlag, revision, jsonFlag] = rest;
      if (revisionFlag !== "--expected-revision" || jsonFlag !== "--json" || rest.length !== 3) {
        commandUsage();
      }
      const payload: ApplyRequest = { expectedRevision: parseRevision(revision) };
      writeJson(await callService("/v1/apply", "POST", payload));
      return 0;
    }
    if (operation === "saved-command") {
      const [savedOperation, ...savedArgs] = rest;
      if (savedOperation === "create" && savedArgs.length === 1 && savedArgs[0] === "--json") {
        const request = await Effect.runPromise(
          parseJson(Schema.Unknown, await Bun.stdin.text(), "saved-command create request"),
        );
        const expectedRevision = await savedCommandRevision();
        writeJson(await callService("/v1/saved-commands/create", "POST", { request, expectedRevision }));
        return 0;
      }
      if (savedOperation === "list" && savedArgs.length === 1 && savedArgs[0] === "--json") {
        writeJson(await callService("/v1/saved-commands", "GET"));
        return 0;
      }
      if (
        savedOperation === "lookup" &&
        savedArgs.length === 2 &&
        savedArgs[1] === "--json"
      ) {
        writeJson(await callService("/v1/saved-commands/lookup", "POST", { id: savedArgs[0] }));
        return 0;
      }
      if (savedOperation === "projection" && savedArgs.length === 1 && savedArgs[0] === "--json") {
        writeJson(await callService("/v1/saved-commands/projection", "GET"));
        return 0;
      }
      commandUsage();
    }
    commandUsage();
  } catch (cause) {
    failure(cause);
    return 1;
  }
}
