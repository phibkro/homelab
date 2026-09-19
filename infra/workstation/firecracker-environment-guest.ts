#!/usr/bin/env bun
import { execFileSync, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { readFileSync } from "node:fs";

const MAX_REQUEST_FRAME = 64 * 1024;
const MAX_RESPONSE_FRAME = 1024 * 1024;
const RPC_TIMEOUT_MS = Number(process.env.ADLC_GUEST_RPC_TIMEOUT_MS ?? 60_000);
const MAX_STDERR = 8 * 1024;

const MAX_ISOLATION_OUTPUT = 8 * 1024;
const hostOnlyPaths = [
  "/home/nori/.ssh/id_ed25519",
  "/run/secrets/host-secret",
  "/run/adlc-firecracker/launcher.sock",
  "/srv/share/projects/adlc-os/package.json",
] as const;

const boundedCommandJson = (arguments_: readonly string[]): unknown => {
  const output = execFileSync("ip", ["-j", ...arguments_], {
    encoding: "utf8",
    maxBuffer: MAX_ISOLATION_OUTPUT,
  });
  if (Buffer.byteLength(output) > MAX_ISOLATION_OUTPUT)
    throw new Error("guest isolation command exceeds limit");
  return JSON.parse(output);
};

const guestStore = () => {
  const entry = readFileSync("/proc/self/mountinfo", "utf8")
    .trim()
    .split("\n")
    .find((line) => line.split(" ")[4] === "/nix/store");
  if (!entry) throw new Error("guest Nix store mount is unavailable");
  const separator = entry.indexOf(" - ");
  if (separator < 0) throw new Error("guest Nix store mount is malformed");
  const fields = entry.slice(separator + 3).split(" ");
  if (fields[0] !== "erofs" || fields[1] !== "/dev/vda")
    throw new Error("guest Nix store is not the read-only guest block device");
  return { source: fields[1], fsType: fields[0], mountPoint: "/nix/store" };
};

const collectIsolation = () => {
  const deniedPaths = hostOnlyPaths.map((path) => {
    try {
      readFileSync(path);
      throw new Error(`guest could read host-only path: ${path}`);
    } catch (error) {
      if (error instanceof Error && error.message === `guest could read host-only path: ${path}`)
        throw error;
      return path;
    }
  });
  const links = boundedCommandJson(["link", "show"]) as Array<Record<string, unknown>>;
  const addresses = boundedCommandJson(["address", "show"]) as Array<Record<string, unknown>>;
  const routes = boundedCommandJson(["route", "show", "table", "all"]) as Array<
    Record<string, unknown>
  >;
  const routes6 = boundedCommandJson(["-6", "route", "show", "table", "all"]) as Array<
    Record<string, unknown>
  >;
  const interfaces = links.map((link) => link.ifname);
  if (interfaces.length !== 1 || interfaces[0] !== "lo")
    throw new Error("guest has a non-loopback network interface");
  const nonLoopbackAddress = addresses.some((entry) =>
    (entry.addr_info as Array<Record<string, unknown>> | undefined)?.some(
      (address) =>
        !(
          (address.family === "inet" && address.local === "127.0.0.1") ||
          (address.family === "inet6" && address.local === "::1")
        ),
    ),
  );
  if (nonLoopbackAddress) throw new Error("guest has a non-loopback network address");
  const allRoutes = [...routes, ...routes6];
  if (allRoutes.some((route) => route.dev !== "lo"))
    throw new Error("guest has an external network route");
  const nameservers = readFileSync("/etc/resolv.conf", "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("nameserver "));
  if (nameservers.length > 0) throw new Error("guest has a DNS resolver");
  return {
    deniedHostPaths: deniedPaths,
    guestStore: guestStore(),
    interfaces,
    addresses,
    routes: allRoutes,
    nameservers,
  };
};
const generation =
  readFileSync("/proc/cmdline", "utf8")
    .split(/\s+/)
    .find((value) => value.startsWith("adlc.generation="))
    ?.slice("adlc.generation=".length) ?? process.env.ADLC_GENERATION;
const generationOrdinal = Number(
  readFileSync("/proc/cmdline", "utf8")
    .split(/\s+/)
    .find((value) => value.startsWith("adlc.generationOrdinal="))
    ?.slice("adlc.generationOrdinal=".length) ?? process.env.ADLC_GENERATION_ORDINAL,
);

if (
  !generation ||
  !/^shg_[a-z0-9][a-z0-9-]{0,62}$/.test(generation) ||
  !Number.isSafeInteger(generationOrdinal) ||
  generationOrdinal <= 0
) {
  throw new Error("missing generation binding");
}

const readLine = async (
  stream: NodeJS.ReadableStream,
  maxFrame = MAX_RESPONSE_FRAME,
  timeoutMessage = "OMP RPC timed out",
): Promise<string> => {
  const { promise, resolve, reject } = Promise.withResolvers<string>();
  let buffer = "";
  let settled = false;
  const timer = setTimeout(() => reject(new Error(timeoutMessage)), RPC_TIMEOUT_MS);
  timer.unref();
  const cleanup = () => {
    clearTimeout(timer);
    stream.off("data", onData);
    stream.off("error", onError);
    stream.off("end", onEnd);
  };
  const settle = (result: () => void) => {
    if (settled) return;
    settled = true;
    cleanup();
    result();
  };
  const onData = (chunk: Buffer | string) => {
    buffer += chunk.toString();
    if (Buffer.byteLength(buffer) > maxFrame) {
      settle(() => reject(new Error("OMP RPC frame exceeds limit")));
      return;
    }
    const end = buffer.indexOf("\n");
    if (end >= 0) settle(() => resolve(buffer.slice(0, end)));
  };
  const onError = (error: Error) => settle(() => reject(error));
  const onEnd = () => settle(() => reject(new Error("stdin closed before frame")));
  stream.on("data", onData);
  stream.once("error", onError);
  stream.once("end", onEnd);
  return promise;
};

const readRequestLine = async (): Promise<string> => {
  let buffer = "";
  const { promise, resolve, reject } = Promise.withResolvers<string>();
  let settled = false;
  const timer = setTimeout(() => reject(new Error("guest request timed out")), RPC_TIMEOUT_MS);
  timer.unref();
  const cleanup = () => {
    clearTimeout(timer);
    process.stdin.off("data", onData);
    process.stdin.off("error", onError);
    process.stdin.off("end", onEnd);
  };
  const settle = (result: () => void) => {
    if (settled) return;
    settled = true;
    cleanup();
    result();
  };
  const onData = (chunk: Buffer | string) => {
    buffer += chunk.toString();
    if (Buffer.byteLength(buffer) > MAX_REQUEST_FRAME) {
      settle(() => reject(new Error("guest request exceeds frame limit")));
      return;
    }
    const end = buffer.indexOf("\n");
    if (end < 0) return;
    if (end !== buffer.length - 1) {
      settle(() => reject(new Error("guest request must be one bounded JSON line")));
      return;
    }
    settle(() => resolve(buffer.slice(0, end)));
  };
  const onError = (error: Error) => settle(() => reject(error));
  const onEnd = () => settle(() => reject(new Error("stdin closed before request")));
  process.stdin.on("data", onData);
  process.stdin.once("error", onError);
  process.stdin.once("end", onEnd);
  return promise;
};

const requestFromStdin = async (): Promise<Record<string, unknown>> => {
  const line = await readRequestLine();
  const parsed: unknown = JSON.parse(line);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    throw new Error("guest request must be an object");
  const request = parsed as Record<string, unknown>;
  const fields = ["_tag", "environmentId", "generation", "requestId", "operation", "payload"];
  if (Object.keys(request).length !== fields.length || fields.some((field) => !(field in request)))
    throw new Error("unknown or missing request fields");
  if (request._tag !== "SelfHostedGuestRpcRequest" || request.operation !== "get_state")
    throw new Error("unsupported guest operation");
  if (
    !request.payload ||
    typeof request.payload !== "object" ||
    Array.isArray(request.payload) ||
    Object.keys(request.payload).length !== 0
  )
    throw new Error("get_state payload must be empty");
  const requestedGeneration = request.generation;
  if (
    !requestedGeneration ||
    typeof requestedGeneration !== "object" ||
    (requestedGeneration as Record<string, unknown>).generationId !== generation ||
    (requestedGeneration as Record<string, unknown>).ordinal !== generationOrdinal
  )
    throw new Error("generation mismatch");
  if (typeof request.requestId !== "string" || request.requestId.length === 0)
    throw new Error("requestId is required");
  return request;
};

const getState = async (requestId: string, observeIsolation: () => unknown): Promise<string> => {
  const omp: ChildProcessWithoutNullStreams = spawn(
    "omp",
    [
      "--mode",
      "rpc",
      "--model",
      "offline/offline",
      "--no-extensions",
      "--no-skills",
      "--no-rules",
      "--no-session",
    ],
    {
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  let exitError: Error | undefined;
  let stderr = "";
  let stderrBytes = 0;
  omp.stderr.on("data", (chunk: Buffer | string) => {
    if (stderrBytes >= MAX_STDERR) return;
    const text = chunk.toString();
    const remaining = MAX_STDERR - stderrBytes;
    stderr += text.slice(0, remaining);
    stderrBytes += Buffer.byteLength(text.slice(0, remaining));
  });
  const diagnostics = (error: unknown) => {
    const code = omp.exitCode;
    const signal = omp.signalCode;
    const status =
      code === null ? (signal ? `signal ${signal}` : "still running") : `exit code ${code}`;
    const detail = stderr.length > 0 ? `; stderr: ${stderr}` : "";
    return new Error(
      `${error instanceof Error ? error.message : "OMP RPC failed"} (${status}${detail})`,
    );
  };
  omp.once("error", (error) => {
    exitError = diagnostics(error);
  });
  const exited = new Promise<never>((_, reject) => {
    omp.once("exit", () => {
      exitError = diagnostics(new Error("OMP exited"));
      reject(exitError);
    });
  });
  const nextLine = () => Promise.race([readLine(omp.stdout), exited]);
  try {
    for (;;) {
      const readyLine = await nextLine();
      try {
        const ready: unknown = JSON.parse(readyLine);
        if (
          ready &&
          typeof ready === "object" &&
          !Array.isArray(ready) &&
          (ready as Record<string, unknown>).type === "ready"
        ) {
          break;
        }
      } catch {}
    }
    omp.stdin.write(`${JSON.stringify({ id: requestId, type: "get_state" })}\n`);
    for (;;) {
      const line = await nextLine();
      const parsed: unknown = JSON.parse(line);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) continue;
      const response = parsed as Record<string, unknown>;
      if (response.id !== requestId) continue;
      if (
        response.type !== "response" ||
        response.command !== "get_state" ||
        response.success !== true ||
        !("data" in response)
      )
        throw new Error("OMP get_state failed");
      let stateJson: string;
      try {
        stateJson = JSON.stringify({ omp: response.data, isolation: observeIsolation() });
      } catch {
        throw new Error("OMP state or guest isolation evidence is not serializable");
      }
      if (typeof stateJson !== "string") throw new Error("OMP get_state data is undefined");
      if (Buffer.byteLength(stateJson) > MAX_RESPONSE_FRAME)
        throw new Error("OMP state exceeds frame limit");
      return stateJson;
    }
  } catch (error) {
    if (error === exitError) throw error;
    throw diagnostics(error);
  } finally {
    if (omp.exitCode === null && omp.signalCode === null) omp.kill("SIGTERM");
  }
};
export const runGuestRpc = async (observeIsolation: () => unknown): Promise<void> => {
  try {
    const request = await requestFromStdin();
    const stateJson = await getState(String(request.requestId), observeIsolation);
    const response = {
      _tag: "SelfHostedGuestRpcResponse",
      environmentId: request.environmentId,
      generation: request.generation,
      requestId: request.requestId,
      operation: "get_state",
      stateJson,
    };
    const output = `${JSON.stringify(response)}\n`;
    if (Buffer.byteLength(output) > MAX_RESPONSE_FRAME)
      throw new Error("guest response exceeds frame limit");
    process.stdout.write(output);
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : "guest RPC failed"}\n`);
    process.exitCode = 1;
  }
};

if (import.meta.main) await runGuestRpc(collectIsolation);
