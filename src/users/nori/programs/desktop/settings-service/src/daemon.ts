/* runtime-adapter: one bounded JSON frame per Unix-socket connection. */
import { chmod, lstat, mkdir, rm } from "node:fs/promises";
import { createServer, type Socket } from "node:net";
import { dirname } from "node:path";
import { Effect, Schema } from "effect";
import {
  ApplyRequest,
  AuthorizationFailureRequest,
  ChangeRequest,
  CreateSavedCommandRequest,
  DesktopSettingsError,
  PreviewRequest,
  ReconcileRequest,
  SavedCommandLookupRequest,
  parseJson,
} from "./contracts.ts";
import { endFrame, maxFrameBytes, readFrame } from "./framing.ts";
import { DesktopSettingsService } from "./service.ts";

export type IpcServer = {
  stop(closeActiveConnections?: boolean): void;
};

const strictParseOptions = {
  errors: "all",
  onExcessProperty: "error",
} as const;

const IpcRequest = Schema.Struct({
  operation: Schema.String,
  payload: Schema.optionalKey(Schema.Unknown),
});
type IpcRequest = typeof IpcRequest.Type;

type JsonResponse = {
  readonly ok: boolean;
  readonly error?: {
    readonly code: string;
    readonly message: string;
    readonly details?: unknown;
  };
  readonly [key: string]: unknown;
};

function asError(cause: unknown): DesktopSettingsError {
  if (cause instanceof DesktopSettingsError) return cause;
  return new DesktopSettingsError(
    "unavailable",
    cause instanceof Error ? cause.message : String(cause),
  );
}

function errorResponse(cause: unknown): JsonResponse {
  const error = asError(cause);
  return error.details === undefined
    ? { ok: false, error: { code: error.code, message: error.message } }
    : { ok: false, error: { code: error.code, message: error.message, details: error.details } };
}

async function payload<A>(request: IpcRequest, schema: Schema.ConstraintDecoder<A>): Promise<A> {
  if (request.payload === undefined) {
    throw new DesktopSettingsError("invalid_request", "IPC operation requires a payload");
  }
  return Effect.runPromise(
    Schema.decodeUnknownEffect(schema, strictParseOptions)(request.payload).pipe(
      Effect.mapError((error) => new DesktopSettingsError("invalid_request", `Invalid request: ${error}`)),
    ),
  );
}

function noPayload(request: IpcRequest): void {
  if (request.payload !== undefined) {
    throw new DesktopSettingsError("invalid_request", "IPC operation does not accept a payload");
  }
}

async function handle(service: DesktopSettingsService, request: IpcRequest): Promise<JsonResponse> {
  switch (request.operation) {
    case "state":
      noPayload(request);
      return { ok: true, state: await service.state() };
    case "change":
      return { ok: true, state: await service.change(await payload(request, ChangeRequest)) };
    case "preview":
      return { ok: true, preview: await service.preview(await payload(request, PreviewRequest)) };
    case "apply":
      return { ok: true, job: await service.apply(await payload(request, ApplyRequest)) };
    case "reconcile":
      return { ok: true, job: await service.reconcile(await payload(request, ReconcileRequest)) };
    case "authorization-failed":
      return { ok: true, job: await service.authorizationFailed(await payload(request, AuthorizationFailureRequest)) };
    case "saved-commands":
      noPayload(request);
      return { ok: true, profile: await service.listSavedCommands() };
    case "saved-commands/create":
      return { ok: true, ...(await service.createSavedCommand(await payload(request, CreateSavedCommandRequest))) };
    case "saved-commands/lookup":
      return { ok: true, ...(await service.lookupSavedCommand(await payload(request, SavedCommandLookupRequest))) };
    case "saved-commands/projection":
      noPayload(request);
      return { ok: true, ...(await service.savedCommandProjection()) };
    default:
      throw new DesktopSettingsError("not_found", `Unknown settings IPC operation: ${request.operation}`);
  }
}

async function decodeRequest(frame: string): Promise<IpcRequest> {
  const value = await Effect.runPromise(parseJson(Schema.Unknown, frame, "IPC request"));
  return Effect.runPromise(
    Schema.decodeUnknownEffect(IpcRequest, strictParseOptions)(value).pipe(
      Effect.mapError((error) => new DesktopSettingsError("invalid_request", `Invalid IPC request: ${error}`)),
    ),
  );
}

async function handleConnection(service: DesktopSettingsService, socket: Socket): Promise<void> {
  try {
    const request = await decodeRequest(await readFrame(socket));
    endFrame(socket, await handle(service, request));
  } catch (cause) {
    endFrame(socket, errorResponse(cause));
  }
}

async function proveSocketIsDead(socket: string): Promise<void> {
  const probe = createServer();
  const { promise, reject, resolve } = Promise.withResolvers<void>();
  probe.once("error", reject);
  probe.listen(socket, () => resolve());
  try {
    await promise;
  } catch (cause) {
    const code = cause instanceof Error && "code" in cause ? cause.code : undefined;
    if (code === "EADDRINUSE") {
      throw new DesktopSettingsError("unavailable", "nori-desktop-config is already running");
    }
    throw cause;
  } finally {
    probe.close();
  }
}

export function isSafeRuntimeDirectory(
  directory: Readonly<{
    isDirectory(): boolean;
    isSymbolicLink(): boolean;
    uid: number;
    mode: number;
  }>,
  currentUid = process.getuid?.(),
): boolean {
  if (!directory.isDirectory() || directory.isSymbolicLink() || directory.uid !== currentUid) return false;
  const mode = directory.mode & 0o777;
  return mode === 0o700 || mode === 0o710 || mode === 0o711;
}

async function prepareSocket(socket: string): Promise<void> {
  const runtimeDirectory = dirname(socket);
  await mkdir(runtimeDirectory, { recursive: true, mode: 0o700 });
  const directory = await lstat(runtimeDirectory);
  if (!isSafeRuntimeDirectory(directory)) {
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
  socketPath: string,
): Promise<IpcServer> {
  await prepareSocket(socketPath);
  const sockets = new Set<Socket>();
  const server = createServer({ allowHalfOpen: true }, (socket) => {
    socket.allowHalfOpen = true;
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
    void handleConnection(service, socket);
  });
  const { promise, reject, resolve } = Promise.withResolvers<void>();
  server.once("error", reject);
  server.listen(socketPath, () => resolve());
  try {
    await promise;
    await chmod(socketPath, 0o600);
  } catch (cause) {
    server.close();
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot bind settings socket: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  return {
    stop(closeActiveConnections = false) {
      if (closeActiveConnections) {
        for (const socket of sockets) socket.destroy();
      }
      server.close();
    },
  };
}

export { maxFrameBytes };
