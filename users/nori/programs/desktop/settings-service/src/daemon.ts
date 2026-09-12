/* runtime-adapter: one-request Unix-socket HTTP boundary around the service. */
import { chmod, lstat, mkdir, rm } from "node:fs/promises";
import { dirname } from "node:path";
import { Effect, Schema } from "effect";
import {
  ApplyRequest,
  ChangeRequest,
  CreateSavedCommandRequest,
  DesktopSettingsError,
  SavedCommandLookupRequest,
  parseJson,
} from "./contracts.ts";
import { DesktopSettingsService } from "./service.ts";
export type IpcServer = {
  stop(closeActiveConnections?: boolean): void;
};


const maxRequestBytes = 64 * 1024;

const strictParseOptions = {
  errors: "all",
  onExcessProperty: "error",
} as const;

type JsonResponse = {
  readonly ok: boolean;
  readonly error?: {
    readonly code: string;
    readonly message: string;
    readonly details?: unknown;
  };
  readonly [key: string]: unknown;
};

function json(response: JsonResponse, status = 200): Response {
  return new Response(`${JSON.stringify(response)}\n`, {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      connection: "close",
    },
  });
}

function asError(cause: unknown): DesktopSettingsError {
  if (cause instanceof DesktopSettingsError) return cause;
  return new DesktopSettingsError(
    "unavailable",
    cause instanceof Error ? cause.message : String(cause),
  );
}

function errorResponse(cause: unknown): Response {
  const error = asError(cause);
  const body =
    error.details === undefined
      ? { ok: false, error: { code: error.code, message: error.message } }
      : { ok: false, error: { code: error.code, message: error.message, details: error.details } };
  const status =
    error.code === "revision_conflict"
      ? 409
      : error.code === "unknown_setting" || error.code === "not_found"
        ? 404
        : error.code === "invalid_profile" || error.code === "invalid_request"
          ? 400
          : 503;
  return json(body, status);
}

async function body<A>(request: Request, schema: Schema.ConstraintDecoder<A>): Promise<A> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null && (!/^\d+$/.test(contentLength) || Number(contentLength) > maxRequestBytes)) {
    throw new DesktopSettingsError("invalid_request", "Request body exceeds the IPC limit");
  }
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength > maxRequestBytes) {
    throw new DesktopSettingsError("invalid_request", "Request body exceeds the IPC limit");
  }
  const parsed = await Effect.runPromise(
    parseJson(Schema.Unknown, new TextDecoder().decode(bytes), "request JSON"),
  );
  return Effect.runPromise(
    Schema.decodeUnknownEffect(schema, strictParseOptions)(parsed).pipe(
      Effect.mapError(
        (error) => new DesktopSettingsError("invalid_request", `Invalid request: ${error}`),
      ),
    ),
  );
}

async function handle(service: DesktopSettingsService, request: Request): Promise<Response> {
  try {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/v1/state") {
      return json({ ok: true, state: await service.state() });
    }
    if (request.method === "POST" && url.pathname === "/v1/change") {
      return json({ ok: true, state: await service.change(await body(request, ChangeRequest)) });
    }
    if (request.method === "POST" && url.pathname === "/v1/preview") {
      return json({ ok: true, preview: await service.preview(await body(request, ChangeRequest)) });
    }
    if (request.method === "POST" && url.pathname === "/v1/apply") {
      return json({ ok: true, job: await service.apply(await body(request, ApplyRequest)) });
    }
    if (request.method === "GET" && url.pathname === "/v1/saved-commands") {
      return json({ ok: true, profile: await service.listSavedCommands() });
    }
    if (request.method === "POST" && url.pathname === "/v1/saved-commands/create") {
      const result = await service.createSavedCommand(await body(request, CreateSavedCommandRequest));
      return json({ ok: true, ...result });
    }
    if (request.method === "POST" && url.pathname === "/v1/saved-commands/lookup") {
      return json({
        ok: true,
        ...(await service.lookupSavedCommand(await body(request, SavedCommandLookupRequest))),
      });
    }
    if (request.method === "GET" && url.pathname === "/v1/saved-commands/projection") {
      return json({ ok: true, ...(await service.savedCommandProjection()) });
    }
    throw new DesktopSettingsError("not_found", `Unknown settings IPC operation: ${request.method} ${url.pathname}`);
  } catch (cause) {
    return errorResponse(cause);
  }
}

async function proveSocketIsDead(socket: string): Promise<void> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 500);
  try {
    await fetch("http://localhost/v1/state", {
      unix: socket,
      signal: controller.signal,
    });
    throw new DesktopSettingsError("unavailable", "nori-desktop-config is already running");
  } catch (cause) {
    if (cause instanceof DesktopSettingsError) throw cause;
    if (controller.signal.aborted) {
      throw new DesktopSettingsError(
        "unavailable",
        "Cannot safely replace an existing settings socket after a timed-out probe",
      );
    }
    const code =
      cause instanceof Error && "code" in cause && typeof cause.code === "string"
        ? cause.code
        : undefined;
    if (code === "ECONNREFUSED" || code === "ENOENT") return;
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot safely replace an existing settings socket: ${
        cause instanceof Error ? cause.message : String(cause)
      }`,
    );
  } finally {
    clearTimeout(timeout);
  }
}

async function prepareSocket(socket: string): Promise<void> {
  const runtimeDirectory = dirname(socket);
  await mkdir(runtimeDirectory, { recursive: true, mode: 0o700 });
  const directory = await lstat(runtimeDirectory);
  if (
    !directory.isDirectory() ||
    directory.isSymbolicLink() ||
    directory.uid !== process.getuid?.() ||
    (directory.mode & 0o077) !== 0
  ) {
    throw new DesktopSettingsError("unavailable", `Refusing unsafe runtime directory: ${runtimeDirectory}`);
  }
  try {
    const current = await lstat(socket);
    if (
      !current.isSocket() ||
      current.isSymbolicLink() ||
      current.uid !== process.getuid?.() ||
      (current.mode & 0o077) !== 0
    ) {
      throw new DesktopSettingsError("unavailable", `Refusing unsafe existing socket: ${socket}`);
    }
    await proveSocketIsDead(socket);
    await rm(socket);
  } catch (cause) {
    if (cause instanceof Error && "code" in cause && cause.code === "ENOENT") return;
    if (cause instanceof DesktopSettingsError) throw cause;
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot prepare settings socket: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
}

export async function startIpcServer(
  service: DesktopSettingsService,
  socket: string,
): Promise<IpcServer> {
  await prepareSocket(socket);
  const originalUmask = process.umask(0o077);
  try {
    const server = Bun.serve({
      unix: socket,
      fetch: (request) => handle(service, request),
      maxRequestBodySize: maxRequestBytes,
    });
    await chmod(socket, 0o600);
    return server;
  } catch (cause) {
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot bind settings socket: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  } finally {
    process.umask(originalUmask);
  }
}
