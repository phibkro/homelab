/* runtime-adapter: installed CLI bridge over one bounded local Unix-socket frame. */
import { createConnection } from "node:net";
import { Effect, Schema } from "effect";
import {
  DesktopSettingsError,
  assertNonNegativeSafeInteger,
  parseJson,
  type ApplyRequest,
  type ChangeRequest,
  type PreviewRequest,
  type ReconcileRequest,
} from "./contracts.ts";
import { DesktopRuntime, type RuntimePaths } from "./runtime.ts";
import { encodeFrame, readFrame, writeFrame } from "./framing.ts";

export type CliRuntime = {
  readonly socket: string;
  readonly halfClose: boolean;
};

function runtimeFromEnvironment(): CliRuntime {
  const configured = process.env.NORI_DESKTOP_SETTINGS_SOCKET;
  if (configured !== undefined && configured.length > 0) {
    return { socket: configured, halfClose: process.env.NORI_DESKTOP_SETTINGS_HALF_CLOSE !== "0" };
  }
  const runtimeDirectory = process.env.XDG_RUNTIME_DIR;
  if (runtimeDirectory === undefined || runtimeDirectory.length === 0) {
    throw new DesktopSettingsError("unavailable", "XDG_RUNTIME_DIR is not configured");
  }
  return {
    socket: `${runtimeDirectory}/nori-desktop/settings.sock`,
    halfClose: process.env.NORI_DESKTOP_SETTINGS_HALF_CLOSE !== "0",
  };
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

function operationFor(path: string, method: "GET" | "POST"): string {
  const operations: Record<string, string> = {
    "GET /v1/state": "state",
    "POST /v1/change": "change",
    "POST /v1/preview": "preview",
    "POST /v1/apply": "apply",
    "POST /v1/reconcile": "reconcile",
    "POST /v1/authorization-failed": "authorization-failed",
    "GET /v1/saved-commands": "saved-commands",
    "POST /v1/saved-commands/create": "saved-commands/create",
    "POST /v1/saved-commands/lookup": "saved-commands/lookup",
    "GET /v1/saved-commands/projection": "saved-commands/projection",
  };
  const operation = operations[`${method} ${path}`];
  if (operation === undefined) {
    throw new DesktopSettingsError("invalid_request", `Unknown settings IPC operation: ${method} ${path}`);
  }
  return operation;
}

async function exchange(
  request: { readonly operation: string; readonly payload?: unknown },
  runtime: CliRuntime,
): Promise<Record<string, unknown>> {
  const socket = createConnection({ path: runtime.socket, allowHalfOpen: true });
  socket.allowHalfOpen = true;
  const { promise, reject, resolve } = Promise.withResolvers<void>();
  socket.once("connect", resolve);
  socket.once("error", reject);
  try {
    await promise;
    const response = readFrame(socket);
    if (runtime.halfClose) socket.end(encodeFrame(request));
    else writeFrame(socket, request);
    return decodeResponse(await response);
  } catch (cause) {
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot contact nori-desktop-config: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  } finally {
    socket.destroy();
  }
}

export async function callService(
  path: string,
  method: "GET" | "POST",
  payload?: unknown,
  runtime = runtimeFromEnvironment(),
): Promise<Record<string, unknown>> {
  const response = await exchange(
    payload === undefined
      ? { operation: operationFor(path, method) }
      : { operation: operationFor(path, method), payload },
    runtime,
  );
  if (response.ok === true) return response;
  throw serviceError(response);
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
    if (operation === "preview") {
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
      const payload: PreviewRequest = {
        component,
        setting,
        value: await parseValue(value),
        expectedRevision: parseRevision(revision),
      };
      writeJson(await callService("/v1/preview", "POST", payload));
      return 0;
    }
    if (operation === "change") {
      const [component, setting, value, revisionFlag, revision, previewFlag, previewId, jsonFlag] = rest;
      if (
        component === undefined ||
        setting === undefined ||
        value === undefined ||
        revisionFlag !== "--expected-revision" ||
        previewFlag !== "--preview" ||
        previewId === undefined ||
        jsonFlag !== "--json" ||
        rest.length !== 8
      ) {
        commandUsage();
      }
      const payload: ChangeRequest = {
        component,
        setting,
        value: await parseValue(value),
        expectedRevision: parseRevision(revision),
        previewId,
      };
      writeJson(await callService("/v1/change", "POST", payload));
      return 0;
    }
    if (operation === "apply") {
      const [revisionFlag, revision, previewFlag, previewId, jsonFlag] = rest;
      if (
        revisionFlag !== "--expected-revision" ||
        previewFlag !== "--preview" ||
        previewId === undefined ||
        jsonFlag !== "--json" ||
        rest.length !== 5
      ) {
        commandUsage();
      }
      const payload: ApplyRequest = { expectedRevision: parseRevision(revision), previewId };
      writeJson(await callService("/v1/apply", "POST", payload));
      return 0;
    }
    if (operation === "authorization-failed") {
      const [idFlag, applyId, jsonFlag] = rest;
      if (idFlag !== "--apply-id" || applyId === undefined || jsonFlag !== "--json" || rest.length !== 3) {
        commandUsage();
      }
      writeJson(await callService("/v1/authorization-failed", "POST", { applyId }));
      return 0;
    }
    if (operation === "reconcile") {
      const [idFlag, applyId, observedFlag, observedText, jsonFlag] = rest;
      if (idFlag !== "--apply-id" || applyId === undefined || observedFlag !== "--observed" || observedText === undefined || jsonFlag !== "--json" || rest.length !== 5) {
        commandUsage();
      }
      const observed = await Effect.runPromise(parseJson(Schema.Unknown, observedText, "Waybar observation"));
      const payload: ReconcileRequest = await Effect.runPromise(
        Schema.decodeUnknownEffect(
          Schema.Struct({ applyId: Schema.String, observed: Schema.Struct({ waybar: Schema.Struct({ unit: Schema.Literals(["active", "inactive", "failed", "unknown"]), edge: Schema.Literals(["top", "bottom", "unavailable"]), reason: Schema.optionalKey(Schema.String) }) }) }),
          { errors: "all", onExcessProperty: "error" },
        )({ applyId, observed }),
      );
      writeJson(await callService("/v1/reconcile", "POST", payload));
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

export async function runRuntimeObservation(
  args: ReadonlyArray<string>,
  paths: RuntimePaths,
): Promise<number> {
  try {
    if (args.length !== 1 || args[0] !== "--json") {
      throw new DesktopSettingsError("invalid_request", "usage: nori-desktop-settings observe-runtime --json");
    }
    const observed = await new DesktopRuntime(paths).observe();
    writeJson(
      await Effect.runPromise(
        Schema.decodeUnknownEffect(
          Schema.Struct({
            waybar: Schema.Struct({
              unit: Schema.Literals(["active", "inactive", "failed", "unknown"]),
              edge: Schema.Literals(["top", "bottom", "unavailable"]),
              reason: Schema.optionalKey(Schema.String),
            }),
          }),
          { errors: "all", onExcessProperty: "error" },
        )(observed),
      ),
    );
    return 0;
  } catch (cause) {
    failure(cause);
    return 1;
  }
}
