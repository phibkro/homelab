#!/usr/bin/env bun
import { createHash } from "node:crypto";
import { createConnection, createServer, type Socket } from "node:net";
import {
  chmodSync,
  closeSync,
  chownSync,
  statSync,
  existsSync,
  fsyncSync,
  linkSync,
  mkdirSync,
  openSync,
  readFileSync,
  readlinkSync,
  readdirSync,
  renameSync,
  rmSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";
import { execFileSync, spawn } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

const MAX_FRAME = 64 * 1024;
const MAX_RESPONSE_FRAME = 1024 * 1024;
const TIMEOUT = 10_000;
const READINESS_TIMEOUT = 90_000;
const GUEST_MEMORY_OVERHEAD_BYTES = 128 * 1024 * 1024;
const GUEST_RPC_TIMEOUT = 60_000;
const MATERIALIZATION_IPC_TIMEOUT = 180_000;
const ID = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const GEN = /^shg_[a-z0-9][a-z0-9-]{0,62}$/;
const DIGEST = /^sha256:[0-9a-f]{64}$/;
const ROOT = process.env.ADLC_STATE_ROOT ?? "/var/lib/adlc-firecracker";
const SOCKET = process.env.ADLC_SOCKET ?? "/run/adlc-firecracker/launcher.sock";
const FC = process.env.ADLC_FIRECRACKER!;
const JAILER = process.env.ADLC_JAILER!;
const KERNEL = process.env.ADLC_GUEST_KERNEL!;
const INITRD = process.env.ADLC_GUEST_INITRD!;
const STORE = process.env.ADLC_GUEST_STORE!;
const BOOT_ARGS = process.env.ADLC_GUEST_BOOT_ARGS;
const UID = Number(process.env.ADLC_GUEST_UID ?? 418);
const GID = Number(process.env.ADLC_GUEST_GID ?? 418);
const SOCKET_GID = Number(process.env.ADLC_SOCKET_GID ?? GID);
const CID = 3;
const PORT = 5000;
const FAILURE_LOG_ROOT = process.env.ADLC_FAILURE_LOG_ROOT;
const CGROUP_ROOT = "/sys/fs/cgroup";
const CGROUP_CONTROLLERS = ["cpu", "io", "memory", "pids"] as const;
export const parseVsockHandshake = (line: string): string => {
  const match = /^OK ([1-9][0-9]*)$/.exec(line);
  if (!match) throw new Error("invalid Firecracker VSOCK handshake");
  return match[1];
};

type Dict = Record<string, unknown>;
const fail = (message: string): never => {
  throw new Error(message);
};
const timestamp = () => new Date().toISOString();
const digest = (bytes: Uint8Array) => `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
const fileDigest = (path: string) => {
  const [hash] = run("sha256sum", ["--", path]).split(/\s+/, 1);
  if (!hash || !/^[0-9a-f]{64}$/.test(hash)) fail("invalid artifact digest");
  return `sha256:${hash}`;
};
const treeDigest = (path: string) => {
  const hash = createHash("sha256");
  for (const entry of readdirSync(path, { recursive: true })
    .sort()
    .map(String)
    .filter((entry) => !entry.endsWith("/state.img") && entry !== "state.img")) {
    hash.update(entry);
    const full = join(path, entry);
    try {
      hash.update(readFileSync(full));
    } catch {}
  }
  return `sha256:${hash.digest("hex")}`;
};
const copyArtifact = (source: string, target: string) => {
  const sourceDigest = fileDigest(source);
  execFileSync("cp", ["--reflink=auto", "--sparse=always", "--", source, target], {
    stdio: "ignore",
  });
  if (fileDigest(target) !== sourceDigest) fail("artifact copy digest mismatch");
  return sourceDigest;
};
const preserveVmmLog = (log: string, environmentId: string, generationId: string) => {
  if (!FAILURE_LOG_ROOT || !existsSync(log)) return;
  mkdirSync(FAILURE_LOG_ROOT, { recursive: true, mode: 0o700 });
  execFileSync(
    "cp",
    [
      "--reflink=auto",
      "--sparse=always",
      "--",
      log,
      join(FAILURE_LOG_ROOT, `${environmentId}-${generationId}.vmm.log`),
    ],
    { stdio: "ignore" },
  );
};
const appendLog = (path: string, chunk: Buffer) => {
  const max = 1024 * 1024;
  const current = existsSync(path) ? readFileSync(path) : Buffer.alloc(0);
  if (current.length < max) writeFileSync(path, Buffer.concat([current, chunk]).subarray(0, max));
};
const exact = (value: unknown, keys: readonly string[], name: string): Dict => {
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail(`${name} must be an object`);
  const result = value as Dict;
  if (Object.keys(result).length !== keys.length || keys.some((key) => !(key in result)))
    fail(`${name} has unknown or missing fields`);
  return result;
};
const checkEnvironmentId = (value: unknown): string => {
  if (typeof value !== "string" || !ID.test(value)) fail("invalid environmentId");
  return value;
};
const checkGeneration = (value: unknown): Dict => {
  const result = exact(value, ["generationId", "ordinal"], "generation");
  if (
    typeof result.generationId !== "string" ||
    !GEN.test(result.generationId) ||
    typeof result.ordinal !== "number" ||
    !Number.isSafeInteger(result.ordinal) ||
    result.ordinal <= 0
  )
    fail("invalid generation");
  return result;
};
const pathFor = (environmentId: string, generationId: string) => {
  checkEnvironmentId(environmentId);
  if (!GEN.test(generationId)) fail("invalid generation");
  return join(ROOT, environmentId, generationId);
};
const environmentPath = (environmentId: string) => {
  checkEnvironmentId(environmentId);
  return join(ROOT, environmentId);
};
const stateImageFor = (environmentId: string) => join(environmentPath(environmentId), "state.img");
const environmentStateFor = (environmentId: string): Dict | undefined => {
  const path = join(environmentPath(environmentId), "environment.json");
  if (!existsSync(path)) return undefined;
  return exact(
    JSON.parse(readFileSync(path, "utf8")),
    ["environmentId", "stateVolumeBytes", "initialStateVolumeDigest"],
    "environment state",
  );
};
const saveEnvironmentState = (environmentId: string, state: Dict) =>
  saveState(environmentPath(environmentId), state, "environment.json");
const stateFor = (environmentId: string, generationId: string): Dict => {
  const path = join(pathFor(environmentId, generationId), "state.json");
  if (!existsSync(path)) fail("generation is not materialized");
  const state = JSON.parse(readFileSync(path, "utf8")) as unknown;
  const result = exact(
    state,
    [
      "environmentId",
      "generation",
      "pid",
      "pidStartTime",
      "pidCgroup",
      "pidNetns",
      "pidExe",
      "netns",
      "cgroupPath",
      "netnsPid",
      "netnsStartTime",
      "netnsExe",
      "draining",
      "receipt",
    ],
    "state",
  );
  const generation = checkGeneration(result.generation);
  if (result.environmentId !== environmentId || generation.generationId !== generationId)
    fail("generation binding mismatch");
  return result;
};
const assertStateGeneration = (state: Dict, environmentId: string, generation: Dict) => {
  const persisted = checkGeneration(state.generation);
  if (
    state.environmentId !== environmentId ||
    generation.generationId !== persisted.generationId ||
    generation.ordinal !== persisted.ordinal
  )
    fail("generation binding mismatch");
};
const saveState = (path: string, state: Dict, file = "state.json") => {
  const target = join(path, file);
  const temporary = `${target}.tmp-${process.pid}-${Date.now()}`;
  writeFileSync(temporary, JSON.stringify(state));
  chmodSync(temporary, 0o600);
  const descriptor = openSync(temporary, "r");
  try {
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  renameSync(temporary, target);
  const directory = openSync(path, "r");
  try {
    fsyncSync(directory);
  } finally {
    closeSync(directory);
  }
};
const live = (pid: number) => {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
};
const recordedPidLive = (value: unknown) => {
  const pid = Number(value);
  return Number.isSafeInteger(pid) && pid > 0 && live(pid);
};
const waitForPidFile = async (path: string) => {
  const deadline = Date.now() + TIMEOUT;
  while (Date.now() < deadline) {
    if (existsSync(path)) {
      const value = readFileSync(path, "utf8").trim();
      if (/^\d+$/.test(value)) return Number(value);
    }
    await sleep(10);
  }
  fail(`process pid file ${path} did not appear after spawn`);
};
const waitForExecutableIdentity = async (
  pid: number,
  description: string,
  executableMatches: (path: string) => boolean,
  fields: { readonly cgroup?: boolean; readonly netns?: boolean } = {},
  child?: ChildProcess,
): Promise<ProcessIdentity> => {
  const deadline = Date.now() + TIMEOUT;
  while (Date.now() < deadline) {
    if (child && (child.exitCode !== null || child.signalCode !== null))
      fail(
        `process ${String(pid)} exited before ${description}: ${child.exitCode === null ? `signal ${String(child.signalCode)}` : `exit ${String(child.exitCode)}`}`,
      );
    if (!live(pid)) fail(`process ${String(pid)} exited before ${description}`);
    try {
      if (executableMatches(processExe(pid))) return observedIdentity(pid, fields);
    } catch {}
    await sleep(10);
  }
  fail(`process ${String(pid)} did not reach ${description}`);
};
const waitForPath = async (path: string) => {
  const deadline = Date.now() + TIMEOUT;
  while (Date.now() < deadline) {
    if (existsSync(path)) return;
    await sleep(10);
  }
  fail(`path ${path} did not appear after spawn`);
};
const processStartTime = (pid: number) => {
  const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
  return stat.slice(stat.lastIndexOf(")") + 2).split(" ")[19];
};
const processCgroup = (pid: number) => readFileSync(`/proc/${pid}/cgroup`, "utf8").trim();
const unifiedCgroupPath = (membership: string) => {
  const hierarchy = membership
    .trim()
    .split("\n")
    .find((entry) => entry.startsWith("0::"));
  if (!hierarchy) fail("launcher requires a unified cgroup v2 hierarchy");
  const path = hierarchy.slice(3);
  if (!path.startsWith("/")) fail("launcher received an invalid unified cgroup path");
  return path;
};
const delegatedParentCgroup = () => {
  const current = unifiedCgroupPath(readFileSync("/proc/self/cgroup", "utf8"));
  if (basename(current) !== "launcher")
    fail("launcher must run in its configured delegated cgroup subgroup");
  const parent = dirname(current);
  if (parent === "/" || parent === ".")
    fail("launcher must run in a delegated systemd subgroup");
  return parent.slice(1);
};
const enableCgroupControllers = (parent: string) => {
  const cgroup = join(CGROUP_ROOT, parent);
  const available = new Set(
    readFileSync(join(cgroup, "cgroup.controllers"), "utf8").trim().split(/\s+/).filter(Boolean),
  );
  const unavailable = CGROUP_CONTROLLERS.filter((controller) => !available.has(controller));
  if (unavailable.length > 0)
    fail(`delegated cgroup lacks required controllers: ${unavailable.join(", ")}`);
  writeFileSync(
    join(cgroup, "cgroup.subtree_control"),
    CGROUP_CONTROLLERS.map((controller) => `+${controller}`).join(" "),
  );
  const enabled = new Set(
    readFileSync(join(cgroup, "cgroup.subtree_control"), "utf8").trim().split(/\s+/).filter(Boolean),
  );
  const missing = CGROUP_CONTROLLERS.filter((controller) => !enabled.has(controller));
  if (missing.length > 0)
    fail(`delegated cgroup did not enable controllers: ${missing.join(", ")}`);
  return cgroup;
};
interface ProcessIdentity {
  readonly pid: number;
  readonly start: string;
  readonly exe: string;
  readonly cgroup?: string;
  readonly netns?: string;
}

const processNetns = (pid: number) => readlinkSync(`/proc/${pid}/ns/net`);
const processExe = (pid: number) => readlinkSync(`/proc/${pid}/exe`);
const processMatches = (
  identity: ProcessIdentity,
  processIsLive = recordedPidLive(identity.pid),
) => {
  try {
    return (
      processIsLive &&
      processStartTime(identity.pid) === identity.start &&
      processExe(identity.pid) === identity.exe &&
      (identity.cgroup === undefined || processCgroup(identity.pid) === identity.cgroup) &&
      (identity.netns === undefined || processNetns(identity.pid) === identity.netns)
    );
  } catch {
    return false;
  }
};
const observedIdentity = (
  pid: number,
  fields: { readonly cgroup?: boolean; readonly netns?: boolean } = {},
): ProcessIdentity => ({
  pid,
  start: processStartTime(pid),
  exe: processExe(pid),
  ...(fields.cgroup ? { cgroup: processCgroup(pid) } : {}),
  ...(fields.netns ? { netns: processNetns(pid) } : {}),
});
const vmmIdentity = (state: Dict): ProcessIdentity => ({
  pid: Number(state.pid),
  start: String(state.pidStartTime),
  cgroup: String(state.pidCgroup),
  netns: String(state.pidNetns),
  exe: String(state.pidExe),
});
const netnsIdentity = (state: Dict): ProcessIdentity => ({
  pid: Number(state.netnsPid),
  start: String(state.netnsStartTime),
  exe: String(state.netnsExe),
});
const terminate = async (identity: ProcessIdentity) => {
  if (!recordedPidLive(identity.pid)) return;
  if (!processMatches(identity))
    fail(`refusing to signal process ${String(identity.pid)} after identity changed`);
  try {
    process.kill(identity.pid, "SIGTERM");
  } catch {}
  const deadline = Date.now() + TIMEOUT;
  while (processMatches(identity) && Date.now() < deadline) await sleep(100);
  if (!processMatches(identity)) return;
  try {
    process.kill(identity.pid, "SIGKILL");
  } catch {}
  const killDeadline = Date.now() + 2_000;
  while (processMatches(identity) && Date.now() < killDeadline) await sleep(100);
  if (processMatches(identity)) fail(`process ${String(identity.pid)} did not terminate`);
};
const terminateChild = async (child: ChildProcess | undefined) => {
  if (
    !child ||
    child.pid === undefined ||
    child.exitCode !== null ||
    child.signalCode !== null
  )
    return;
  child.kill("SIGTERM");
  const deadline = Date.now() + TIMEOUT;
  while (child.exitCode === null && child.signalCode === null && Date.now() < deadline)
    await sleep(100);
  if (child.exitCode === null && child.signalCode === null) {
    child.kill("SIGKILL");
    const killDeadline = Date.now() + 2_000;
    while (
      child.exitCode === null &&
      child.signalCode === null &&
      Date.now() < killDeadline
    )
      await sleep(100);
  }
  if (child.exitCode === null && child.signalCode === null)
    fail(`child process ${String(child.pid)} did not terminate after SIGKILL`);
};
const checkedGenerationCgroup = (cgroupPath: string) => {
  const delegatedRoot = join(CGROUP_ROOT, delegatedParentCgroup());
  if (dirname(cgroupPath) !== delegatedRoot)
    fail(`generation cgroup is outside delegated root: ${cgroupPath}`);
  return cgroupPath;
};
const killGenerationCgroup = async (cgroupPath: string) => {
  if (cgroupPath.length === 0) return;
  const cgroup = checkedGenerationCgroup(cgroupPath);
  if (!existsSync(cgroup)) return;
  const killPath = join(cgroup, "cgroup.kill");
  if (existsSync(killPath)) writeFileSync(killPath, "1");
  const deadline = Date.now() + TIMEOUT;
  const populated = () =>
    existsSync(cgroup) &&
    /(?:^|\n)populated 1(?:\n|$)/.test(readFileSync(join(cgroup, "cgroup.events"), "utf8"));
  while (populated() && Date.now() < deadline) await sleep(100);
  if (populated()) fail(`generation cgroup remained populated: ${cgroup}`);
};
const removeGenerationCgroup = async (cgroupPath: string) => {
  if (cgroupPath.length === 0) return;
  const cgroup = checkedGenerationCgroup(cgroupPath);
  await killGenerationCgroup(cgroup);
  if (existsSync(cgroup)) rmdirSync(cgroup);
};
const run = (program: string, args: string[]) =>
  execFileSync(program, args, {
    encoding: "utf8",
    maxBuffer: MAX_FRAME,
  }).trim();
const cleanup = async (
  path: string,
  identities: readonly ProcessIdentity[],
  cgroupPath: string,
  removePath = true,
) => {
  await removeGenerationCgroup(cgroupPath);
  for (const identity of identities) await terminate(identity);
  if (removePath && existsSync(path)) rmSync(path, { recursive: true, force: true });
};
const stateNetnsLive = (state: Dict, processIsLive = recordedPidLive(state.netnsPid)) =>
  processMatches(netnsIdentity(state), processIsLive);
const stateVmmLive = (state: Dict, processIsLive = recordedPidLive(state.pid)) =>
  processMatches(vmmIdentity(state), processIsLive);
const verifiedVmmLive = (state: Dict) => {
  const rawLive = recordedPidLive(state.pid);
  if (!rawLive) return false;
  if (!stateVmmLive(state, rawLive))
    fail("recorded VMM process identity mismatch; launcher action unavailable");
  return true;
};
const verifiedNetnsLive = (state: Dict) => {
  const rawLive = recordedPidLive(state.netnsPid);
  if (!rawLive) return false;
  if (!stateNetnsLive(state, rawLive))
    fail("recorded netns keeper identity mismatch; launcher action unavailable");
  return true;
};
const frame = async (socket: Socket): Promise<string> => {
  const { promise, resolve, reject } = Promise.withResolvers<string>();
  let data = "";
  let settled = false;
  let timer: NodeJS.Timeout | undefined;
  const finish = (error?: Error, value?: string) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    if (error) {
      socket.destroy();
      reject(error);
    } else {
      resolve(value!);
    }
  };
  timer = setTimeout(() => finish(new Error("request timed out")), TIMEOUT);
  socket.on("data", (chunk) => {
    data += chunk.toString();
    if (Buffer.byteLength(data) > MAX_FRAME) {
      finish(new Error("request exceeds frame limit"));
      return;
    }
    const end = data.indexOf("\n");
    if (end >= 0) finish(undefined, data.slice(0, end));
  });
  socket.once("error", (error) => finish(error));
  socket.once("end", () => finish(new Error("request closed without a frame")));
  return promise;
};
const rpc = async (request: Dict, state: Dict): Promise<Dict> => {
  const id = checkEnvironmentId(request.environmentId);
  const generation = checkGeneration(request.generation);
  const generationId = String(generation.generationId);
  assertStateGeneration(state, id, generation);
  if (state.draining === true) fail("generation is draining");
  if (!verifiedVmmLive(state)) fail("generation process identity mismatch");
  const payload = request.payload;
  if (
    !payload ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    Object.keys(payload).length !== 0
  )
    fail("get_state payload must be empty");
  if (request.operation !== "get_state") fail("unsupported RPC operation");
  if (typeof request.requestId !== "string" || request.requestId.length === 0)
    fail("requestId is required");
  const socketPath = `/proc/${Number(state.pid)}/root/vsock.sock`;
  const { promise, resolve, reject } = Promise.withResolvers<Dict>();
  let data = Buffer.alloc(0);
  let handshake = true;
  let settled = false;
  const client = createConnection(socketPath);
  let timer: NodeJS.Timeout | undefined;
  const finish = (error?: Error, result?: Dict) => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    client.destroy();
    if (error) reject(error);
    else resolve(result!);
  };
  const armTimeout = (timeout: number) => {
    clearTimeout(timer);
    timer = setTimeout(
      () =>
        finish(
          new Error(
            `guest RPC timed out${handshake ? `; handshakeRaw=${JSON.stringify(data.subarray(0, 4096).toString())}` : ""}`,
          ),
        ),
      timeout,
    );
  };
  armTimeout(TIMEOUT);
  client.once("error", (error) => finish(error));
  const closedBeforeResponse = () =>
    new Error(
      `guest RPC closed before ${handshake ? "handshake" : "response"}; raw=${JSON.stringify(data.subarray(0, 4096).toString())}`,
    );
  client.once("end", () => finish(closedBeforeResponse()));
  client.once("close", (hadError) => {
    if (!hadError) finish(closedBeforeResponse());
  });
  client.on("connect", () => client.write(`CONNECT ${PORT}\n`));
  client.on("data", (chunk) => {
    if (settled) return;
    data = Buffer.concat([data, chunk]);
    if (data.length > MAX_RESPONSE_FRAME) {
      finish(new Error("guest response exceeds frame limit"));
      return;
    }
    if (handshake) {
      const end = data.indexOf(10);
      if (end < 0) return;
      const line = data.subarray(0, end).toString();
      data = data.subarray(end + 1);
      try {
        parseVsockHandshake(line);
      } catch {
        finish(
          new Error(`guest vsock handshake failed; raw=${JSON.stringify(line.slice(0, 4096))}`),
        );
        return;
      }
      handshake = false;
      armTimeout(GUEST_RPC_TIMEOUT);
      client.write(`${JSON.stringify(request)}\n`);
    }
    const end = data.indexOf(10);
    if (end < 0) return;
    try {
      const result = exact(
        JSON.parse(data.subarray(0, end).toString()) as unknown,
        ["_tag", "environmentId", "generation", "requestId", "operation", "stateJson"],
        "guest response",
      );
      if (
        result._tag !== "SelfHostedGuestRpcResponse" ||
        result.environmentId !== id ||
        (result.generation as Dict).generationId !== generationId ||
        result.requestId !== request.requestId ||
        result.operation !== "get_state" ||
        typeof result.stateJson !== "string"
      )
        fail("guest response generation mismatch");
      finish(undefined, result);
    } catch (error) {
      finish(error instanceof Error ? error : new Error("guest response failed"));
    }
  });
  return promise;
};
const waitForGuestReady = async (state: Dict): Promise<Dict> => {
  const deadline = Date.now() + READINESS_TIMEOUT;
  while (Date.now() < deadline) {
    try {
      return await rpc(
        {
          _tag: "SelfHostedGuestRpcRequest",
          environmentId: state.environmentId,
          generation: state.generation,
          requestId: `ready-${Date.now()}`,
          operation: "get_state",
          payload: {},
        },
        state,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      const transient =
        (error !== null &&
          typeof error === "object" &&
          "code" in error &&
          (error.code === "ECONNREFUSED" ||
            error.code === "ECONNRESET" ||
            error.code === "ENOENT")) ||
        message === 'guest RPC timed out; handshakeRaw=""' ||
        message.startsWith("guest RPC closed before");
      if (!transient) throw error;
      await sleep(100);
    }
  }
  fail("guest OMP readiness deadline exceeded");
};
const observe = async (idValue: unknown, generationValue: unknown): Promise<Dict> => {
  const id = checkEnvironmentId(idValue);
  const generation = checkGeneration(generationValue);
  const state = stateFor(id, String(generation.generationId));
  const running = verifiedVmmLive(state);
  verifiedNetnsLive(state);
  let ready = false;
  if (running && !state.draining) {
    try {
      await rpc(
        {
          _tag: "SelfHostedGuestRpcRequest",
          environmentId: id,
          generation,
          requestId: `ready-${Date.now()}`,
          operation: "get_state",
          payload: {},
        },
        state,
      );
      ready = true;
    } catch {}
  }
  const t = timestamp();
  const validUntil = new Date(Date.now() + 5_000).toISOString();
  return {
    _tag: "EnvironmentObservation",
    environmentId: id,
    generation,
    lifecycle: running ? (state.draining ? "Draining" : "Ready") : "Stopped",
    vmmProcessTreeLive: running,
    ompRpcReady: ready,
    cgroupCounters: {
      _tag: "CgroupCountersUnavailable",
      reason: "not exposed by launcher",
    },
    observedAt: t,
    validUntil,
  };
};
const persistedReceiptFor = (
  state: Dict,
  environmentId: string,
  generation: Dict,
): Dict | undefined => {
  const receipt = state.receipt;
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) return undefined;
  const value = receipt as Dict;
  if (value._tag !== "MaterializationReceipt" || value.environmentId !== environmentId)
    return undefined;
  try {
    const recordedGeneration = checkGeneration(value.generation);
    if (
      recordedGeneration.generationId !== generation.generationId ||
      recordedGeneration.ordinal !== generation.ordinal
    )
      return undefined;
  } catch {
    return undefined;
  }
  return value;
};
const reconcile = async (idValue: unknown, generationValue: unknown): Promise<Dict> => {
  const id = checkEnvironmentId(idValue);
  const generation = checkGeneration(generationValue);
  const generationId = String(generation.generationId);
  const path = pathFor(id, generationId);
  if (!existsSync(join(path, "state.json"))) return { _tag: "SelfHostedGenerationAbsent" };
  const state = stateFor(id, generationId);
  assertStateGeneration(state, id, generation);
  const vmmLive = verifiedVmmLive(state);
  const netnsLive = verifiedNetnsLive(state);
  if (!vmmLive) return { _tag: "SelfHostedGenerationDead" };
  const receipt = persistedReceiptFor(state, id, generation);
  if (!netnsLive || !receipt || state.draining === true)
    return { _tag: "SelfHostedGenerationNotReady" };
  let guestReady = false;
  try {
    const response = await rpc(
      {
        _tag: "SelfHostedGuestRpcRequest",
        environmentId: id,
        generation,
        requestId: `reconcile-${Date.now()}`,
        operation: "get_state",
        payload: {},
      },
      state,
    );
    guestReady = typeof response.stateJson === "string" && response.stateJson.length > 0;
  } catch {}
  const vmmStillLive = verifiedVmmLive(state);
  const netnsStillLive = verifiedNetnsLive(state);
  if (!vmmStillLive) return { _tag: "SelfHostedGenerationDead" };
  if (!netnsStillLive || !guestReady) return { _tag: "SelfHostedGenerationNotReady" };
  return { _tag: "SelfHostedGenerationReady", receipt };
};
const materialize = async (request: Dict): Promise<Dict> => {
  const spec = exact(
    request.spec,
    [
      "_tag",
      "environmentId",
      "organizationId",
      "projectId",
      "workId",
      "actorId",
      "sessionId",
      "policy",
      "policyDigest",
      "guestKernelDigest",
      "guestInitrdDigest",
      "guestStoreDigest",
      "stateVolumeTemplateDigest",
      "harnessDigest",
      "profileDigest",
      "capabilityManifestDigest",
      "networkMode",
      "resources",
      "specificationDigest",
    ],
    "spec",
  );
  const id = checkEnvironmentId(spec.environmentId);
  const generation = checkGeneration(request.generation);
  const generationId = String(generation.generationId);
  const rawJailerId = generationId.replaceAll("_", "-");
  const jailerId =
    rawJailerId.length <= 64
      ? rawJailerId
      : `shg-${createHash("sha256").update(generationId).digest("hex").slice(0, 60)}`;
  if (spec._tag !== "SelfHostedEnvironmentSpec" || spec.networkMode !== "off")
    fail("invalid environment spec");
  const resource = exact(
    spec.resources,
    [
      "cpuMaxMicros",
      "cpuWeight",
      "memoryHighBytes",
      "memoryMaxBytes",
      "vmmProcessTreePidsMax",
      "stateVolumeBytes",
      "ioMaxBytesPerSecond",
    ],
    "resources",
  );
  for (const value of Object.values(resource))
    if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0)
      fail("invalid resource limit");
  if (
    Number(resource.cpuMaxMicros) > 8_000_000 ||
    Number(resource.cpuWeight) > 10_000 ||
    Number(resource.memoryMaxBytes) < GUEST_MEMORY_OVERHEAD_BYTES + 128 * 1024 * 1024 ||
    Number(resource.memoryMaxBytes) > 4 * 1024 * 1024 * 1024 ||
    Number(resource.memoryHighBytes) > Number(resource.memoryMaxBytes) ||
    Number(resource.vmmProcessTreePidsMax) < 16 ||
    Number(resource.vmmProcessTreePidsMax) > 4096 ||
    Number(resource.stateVolumeBytes) > 64 * 1024 * 1024 * 1024 ||
    Number(resource.ioMaxBytesPerSecond) > 1024 * 1024 * 1024
  )
    fail("resource limits exceed host policy");
  for (const artifact of [FC, JAILER, KERNEL, INITRD, STORE])
    if (!existsSync(artifact)) fail("required guest artifact unavailable");
  if (!existsSync("/dev/kvm")) fail("/dev/kvm unavailable");
  if (spec.guestInitrdDigest !== fileDigest(INITRD)) fail("guest initrd digest mismatch");
  if (spec.guestKernelDigest !== fileDigest(KERNEL)) fail("guest kernel digest mismatch");
  if (spec.guestStoreDigest !== fileDigest(STORE)) fail("guest store digest mismatch");
  const stateTemplate = digest(
    Buffer.from(JSON.stringify({ fsType: "ext4", sizeBytes: resource.stateVolumeBytes })),
  );
  if (spec.stateVolumeTemplateDigest !== stateTemplate)
    fail("state volume template digest mismatch");
  const envPath = environmentPath(id);
  const path = pathFor(id, generationId);
  mkdirSync(envPath, { recursive: true, mode: 0o700 });
  mkdirSync(path, { recursive: true, mode: 0o700 });
  if (existsSync(join(path, "state.json"))) {
    const existing = stateFor(id, generationId);
    assertStateGeneration(existing, id, generation);
    if (existing.receipt !== null) {
      const receipt = persistedReceiptFor(existing, id, generation);
      if (receipt && receipt.specificationDigest === spec.specificationDigest) return receipt;
      fail("generation already has a materialization receipt");
    }
    const vmmLive = verifiedVmmLive(existing);
    const netnsLive = verifiedNetnsLive(existing);
    if (vmmLive) fail("refusing materialization replacement for a verified live VMM");
    await cleanup(
      path,
      [...(netnsLive ? [netnsIdentity(existing)] : [])],
      String(existing.cgroupPath),
    );
  }
  else {
    rmSync(path, { recursive: true, force: true });
    mkdirSync(path, { recursive: true, mode: 0o700 });
  }
  const existingEnvironment = environmentStateFor(id);
  if (existingEnvironment && existingEnvironment.stateVolumeBytes !== resource.stateVolumeBytes)
    fail("environment state volume size mismatch");
  const stateImage = stateImageFor(id);
  let initialStateVolumeDigest: string;
  if (!existsSync(stateImage)) {
    run("truncate", ["-s", String(resource.stateVolumeBytes), stateImage]);
    run("mkfs.ext4", ["-F", "-q", "-L", `adlc-${id}`, stateImage]);
    chmodSync(stateImage, 0o660);
    chownSync(stateImage, UID, GID);
    initialStateVolumeDigest = fileDigest(stateImage);
    saveEnvironmentState(id, {
      environmentId: id,
      stateVolumeBytes: resource.stateVolumeBytes,
      initialStateVolumeDigest,
    });
  } else {
    if (statSync(stateImage).size !== Number(resource.stateVolumeBytes))
      fail("state image size mismatch");
    chmodSync(stateImage, 0o660);
    chownSync(stateImage, UID, GID);
    initialStateVolumeDigest = existingEnvironment
      ? String(existingEnvironment.initialStateVolumeDigest)
      : fileDigest(stateImage);
    if (!existingEnvironment)
      saveEnvironmentState(id, {
        environmentId: id,
        stateVolumeBytes: resource.stateVolumeBytes,
        initialStateVolumeDigest,
      });
  }
  mkdirSync(join(path, "jailer", "firecracker", jailerId, "root"), {
    recursive: true,
    mode: 0o700,
  });
  const root = join(path, "jailer", "firecracker", jailerId, "root");
  let namespace = "";
  let keeperChild: ChildProcess | undefined;
  let jailerChild: ChildProcess | undefined;
  let keeperProcess: ProcessIdentity | undefined;
  let vmmProcess: ProcessIdentity | undefined;
  let generationCgroup = "";
  try {
    const artifactDigests: Record<string, string> = {};
    for (const [source, target] of [
      [KERNEL, "vmlinux"],
      [INITRD, "initrd"],
      [STORE, "nix-store.erofs"],
    ] as const) {
      artifactDigests[target] = copyArtifact(source, join(root, target));
    }
    const image = join(root, "state.img");
    linkSync(stateImage, image);
    const mountedSource = run("findmnt", ["-no", "SOURCE", "-T", path]);
    const blockDevice = mountedSource.split("[", 1)[0];
    const parentDevice = run("lsblk", ["-no", "PKNAME", blockDevice]);
    const ioBlockDevice = parentDevice ? `/dev/${parentDevice}` : blockDevice;
    const device = run("lsblk", ["-no", "MAJ:MIN", ioBlockDevice]).split(/\s+/)[0];
    if (!/^\d+:\d+$/.test(device)) fail("unable to identify state backing device");
    const controls = {
      cpuMax: `${resource.cpuMaxMicros} 1000000`,
      cpuWeight: String(resource.cpuWeight),
      memoryHigh: String(resource.memoryHighBytes),
      memoryMax: String(resource.memoryMaxBytes),
      pidsMax: String(resource.vmmProcessTreePidsMax),
      ioMax: `${device} rbps=${resource.ioMaxBytesPerSecond} wbps=${resource.ioMaxBytesPerSecond}`,
    };
    writeFileSync(
      join(root, "config.json"),
      JSON.stringify({
        "boot-source": {
          kernel_image_path: "/vmlinux",
          initrd_path: "/initrd",
          boot_args: `${BOOT_ARGS ?? fail("missing guest boot args")} adlc.generation=${generationId} adlc.generationOrdinal=${String(generation.ordinal)}`,
        },
        "machine-config": {
          vcpu_count: Math.max(1, Math.floor(Number(resource.cpuMaxMicros) / 1_000_000)),
          mem_size_mib: Math.floor(
            (Number(resource.memoryMaxBytes) - GUEST_MEMORY_OVERHEAD_BYTES) / 1048576,
          ),
          smt: false,
        },
        drives: [
          {
            drive_id: "store",
            path_on_host: "/nix-store.erofs",
            is_root_device: false,
            is_read_only: true,
          },
          {
            drive_id: "state",
            path_on_host: "/state.img",
            is_root_device: false,
            is_read_only: false,
          },
        ],
        "network-interfaces": [],
        vsock: { guest_cid: CID, uds_path: "/vsock.sock" },
      }),
    );
    chownSync(root, UID, GID);
    chmodSync(root, 0o755);
    const parentCgroup = delegatedParentCgroup();
    const delegatedRoot = enableCgroupControllers(parentCgroup);
    generationCgroup = join(delegatedRoot, jailerId);
    if (existsSync(generationCgroup)) fail("generation cgroup already exists");
    const state: Dict = {
      environmentId: id,
      generation,
      pid: 0,
      pidStartTime: "",
      pidCgroup: "",
      pidNetns: "",
      pidExe: JAILER,
      netns: "",
      cgroupPath: generationCgroup,
      netnsPid: 0,
      netnsStartTime: "",
      netnsExe: "",
      draining: false,
      receipt: null,
    };
    saveState(path, state);
    const log = join(path, "vmm.log");
    mkdirSync(generationCgroup);
    for (const [file, value] of Object.entries({
      "cpu.max": controls.cpuMax,
      "cpu.weight": controls.cpuWeight,
      "memory.high": controls.memoryHigh,
      "memory.max": controls.memoryMax,
      "pids.max": controls.pidsMax,
      "io.max": controls.ioMax,
    }))
      writeFileSync(join(generationCgroup, file), value);
    keeperChild = spawn("unshare", ["--net", "sleep", "1000000"], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    if (keeperChild.pid === undefined) fail("netns keeper did not report a pid");
    keeperChild.stderr?.on("data", (chunk) => appendLog(log, chunk));
    writeFileSync(join(generationCgroup, "cgroup.procs"), String(keeperChild.pid));
    keeperProcess = await waitForExecutableIdentity(
      keeperChild.pid,
      "the netns keeper payload",
      (path) => basename(path) !== "unshare",
      {},
      keeperChild,
    );
    namespace = `/proc/${keeperChild.pid}/ns/net`;
    Object.assign(state, {
      netns: namespace,
      netnsPid: keeperProcess.pid,
      netnsStartTime: keeperProcess.start,
      netnsExe: keeperProcess.exe,
    });
    saveState(path, state);
    jailerChild = spawn(
      JAILER,
      [
        "--id",
        jailerId,
        "--exec-file",
        FC,
        "--uid",
        String(UID),
        "--gid",
        String(GID),
        "--cgroup-version",
        "2",
        "--parent-cgroup",
        join(parentCgroup, jailerId),
        "--netns",
        namespace,
        "--chroot-base-dir",
        join(path, "jailer"),
        "--resource-limit",
        "no-file=1024",
        "--new-pid-ns",
        "--",
        "--config-file",
        "/config.json",
        "--api-sock",
        "/api.sock",
      ],
      { cwd: root, stdio: ["ignore", "pipe", "pipe"] },
    );
    jailerChild.stdout?.on("data", (chunk) => appendLog(log, chunk));
    jailerChild.stderr?.on("data", (chunk) => appendLog(log, chunk));
    if (jailerChild.pid === undefined) fail("Jailer did not report a pid");
    const vmmPid = await waitForPidFile(join(root, "firecracker.pid"));
    vmmProcess = await waitForExecutableIdentity(
      vmmPid,
      "Firecracker exec",
      (path) => basename(path) === "firecracker",
      { cgroup: true, netns: true },
    );
    const cgroup = `${CGROUP_ROOT}${unifiedCgroupPath(vmmProcess.cgroup!)}`;
    if (cgroup !== generationCgroup)
      fail("VMM escaped the generation resource-control cgroup");
    const effective = Object.fromEntries(
      Object.entries({
        cpuMax: "cpu.max",
        cpuWeight: "cpu.weight",
        memoryHigh: "memory.high",
        memoryMax: "memory.max",
        pidsMax: "pids.max",
        ioMax: "io.max",
      }).map(([key, file]) => [
        key,
        readFileSync(join(generationCgroup, file), "utf8").trim(),
      ]),
    );
    Object.assign(state, {
      pid: vmmProcess.pid,
      pidStartTime: vmmProcess.start,
      pidCgroup: vmmProcess.cgroup,
      pidNetns: vmmProcess.netns,
      pidExe: vmmProcess.exe,
    });
    saveState(path, state);
    const ready = await waitForGuestReady(state);
    if (!ready.stateJson) fail("guest OMP readiness failed");
    const receipt = {
      _tag: "MaterializationReceipt",
      environmentId: id,
      generation,
      specificationDigest: spec.specificationDigest,
      launcherIdentity: fileDigest(import.meta.path),
      firecrackerIdentity: fileDigest(FC),
      jailerRootIdentity: treeDigest(join(path, "jailer")),
      effectiveUid: UID,
      effectiveGid: GID,
      cgroupPath: cgroup,
      cgroupControls: effective,
      kernelDigest: artifactDigests.vmlinux,
      initrdDigest: artifactDigests.initrd,
      storeDigest: artifactDigests["nix-store.erofs"],
      initialStateVolumeDigest,
      vsockCid: CID,
      vsockPort: PORT,
      guestBlockDevices: ["/dev/vda", "/dev/vdb"],
      networkDevicePresent: false,
      metadataServicePresent: false,
      ompReadinessProbeSucceeded: true,
      materializedAt: timestamp(),
    };
    saveState(path, { ...state, receipt });
    return receipt;
  } catch (error) {
    const log = join(path, "vmm.log");
    const details: string[] = [];
    if (existsSync(log)) {
      try {
        details.push(`VMM log: ${readFileSync(log, "utf8").slice(-4 * 1024)}`);
      } catch (diagnosticError) {
        details.push(
          `VMM log read failed: ${diagnosticError instanceof Error ? diagnosticError.message : String(diagnosticError)}`,
        );
      }
    }
    try {
      preserveVmmLog(log, id, String(generation.generationId));
    } catch (preservationError) {
      details.push(
        `VMM log preservation failed: ${preservationError instanceof Error ? preservationError.message : String(preservationError)}`,
      );
    }
    try {
      await terminateChild(jailerChild);
      await terminateChild(keeperChild);
      await cleanup(
        path,
        [vmmProcess, keeperProcess].filter(
          (identity): identity is ProcessIdentity => identity !== undefined,
        ),
        generationCgroup,
      );
    } catch (cleanupError) {
      details.push(
        `cleanup failed: ${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`,
      );
    }
    const message = error instanceof Error ? error.message : "materialization failed";
    throw new Error(`${message}${details.length > 0 ? `; ${details.join("; ")}` : ""}`);
  }
};
export const runLauncherAction = async (request: unknown): Promise<Dict> => {
  if (!request || typeof request !== "object" || Array.isArray(request))
    fail("request must be an object");
  const value = request as Dict;
  if (typeof value.action !== "string") fail("request action is required");
  const action = value.action;
  if (action === "materialize") return materialize(value);
  if (action === "reconcile") {
    exact(value, ["action", "environmentId", "generation"], action);
    return reconcile(value.environmentId, value.generation);
  }
  if (action === "probe" || action === "observe" || action === "drain" || action === "stop") {
    exact(value, ["action", "environmentId", "generation"], String(action));
    const id = checkEnvironmentId(value.environmentId);
    const generation = checkGeneration(value.generation);
    const generationId = String(generation.generationId);
    const state = stateFor(id, generationId);
    assertStateGeneration(state, id, generation);
    if (action === "probe") return { ready: (await observe(id, generation)).ompRpcReady };
    if (action === "observe") return observe(id, generation);
    if (action === "drain") {
      state.draining = true;
      saveState(pathFor(id, generationId), state);
      return { ok: true };
    }
    verifiedVmmLive(state);
    const netnsLive = verifiedNetnsLive(state);
    await killGenerationCgroup(String(state.cgroupPath));
    if (netnsLive) await terminate(netnsIdentity(state));
    return { ok: true };
  }
  if (action === "destroy") {
    exact(
      value,
      value.generation === undefined
        ? ["action", "environmentId"]
        : ["action", "environmentId", "generation"],
      "destroy",
    );
    const id = checkEnvironmentId(value.environmentId);
    const root = environmentPath(id);
    const requestedGeneration =
      value.generation === undefined ? undefined : checkGeneration(value.generation);
    const ids = requestedGeneration
      ? [String(requestedGeneration.generationId)]
      : existsSync(root)
        ? readdirSync(root).filter((entry) => GEN.test(entry))
        : [];
    for (const generationId of ids) {
      const generationPath = pathFor(id, generationId);
      if (!existsSync(generationPath)) continue;
      if (!existsSync(join(generationPath, "state.json"))) {
        rmSync(generationPath, { recursive: true, force: true });
        continue;
      }
      const state = stateFor(id, generationId);
      if (requestedGeneration) assertStateGeneration(state, id, requestedGeneration);
      if (
        (live(Number(state.pid)) && !stateVmmLive(state)) ||
        (live(Number(state.netnsPid)) && !stateNetnsLive(state))
      )
        fail("refusing destroy for an unverified process identity");
      await cleanup(
        generationPath,
        [
          ...(stateVmmLive(state) ? [vmmIdentity(state)] : []),
          ...(stateNetnsLive(state) ? [netnsIdentity(state)] : []),
        ],
        String(state.cgroupPath),
      );
    }
    if (value.generation === undefined && existsSync(root)) {
      const remaining = readdirSync(root).filter((entry) => GEN.test(entry));
      if (remaining.length === 0) rmSync(root, { recursive: true, force: true });
    }
    return { ok: true };
  }
  if (action === "rpc") {
    exact(value, ["action", "frame"], action);
    const request = exact(
      value.frame,
      ["_tag", "environmentId", "generation", "requestId", "operation", "payload"],
      "frame",
    );
    return rpc(
      request,
      stateFor(
        checkEnvironmentId(request.environmentId),
        String(checkGeneration(request.generation).generationId),
      ),
    );
  }
  fail("unknown launcher action");
};
let controlQueue: Promise<void> = Promise.resolve();
const serialized = <T>(task: () => Promise<T>) => {
  const result = controlQueue.then(task, task);
  controlQueue = result.then(
    () => undefined,
    () => undefined,
  );
  return result;
};
const serve = () => {
  if (process.getuid?.() !== 0) fail("daemon must run as root");
  mkdirSync(dirname(SOCKET), { recursive: true, mode: 0o755 });
  try {
    unlinkSync(SOCKET);
  } catch {}
  const server = createServer(async (socket) => {
    try {
      const request = JSON.parse(await frame(socket));
      const response = await serialized(() => runLauncherAction(request));
      socket.end(`${JSON.stringify(response)}\n`);
    } catch (error) {
      socket.end(
        `${JSON.stringify({ error: error instanceof Error ? error.message : "launcher failure" })}\n`,
      );
    }
  });
  server.listen(SOCKET, () => {
    chownSync(SOCKET, 0, SOCKET_GID);
    chmodSync(SOCKET, 0o660);
    console.error(`launcher listening on ${SOCKET}`);
  });
};
if (import.meta.main) {
  if (process.argv.includes("--daemon")) {
    serve();
  } else {
    const input = readFileSync(0);
    if (
      input.length > MAX_FRAME ||
      !input.toString().endsWith("\n") ||
      input.toString().slice(0, -1).includes("\n")
    )
      fail("stdin must contain exactly one bounded JSON line");
    if (process.getuid?.() === 0) {
      runLauncherAction(JSON.parse(input.toString().slice(0, -1)))
        .then((response) => console.log(JSON.stringify(response)))
        .catch((error) => {
          console.error(error.message);
          process.exit(1);
        });
    } else {
      const socket = createConnection(SOCKET);
      let output = "";
      const timer = setTimeout(() => {
        socket.destroy();
        console.error("launcher daemon timed out");
        process.exit(1);
      }, MATERIALIZATION_IPC_TIMEOUT);
      socket.on("connect", () => socket.write(input));
      socket.on("data", (chunk) => {
        output += chunk.toString();
        if (Buffer.byteLength(output) > MAX_RESPONSE_FRAME) {
          socket.destroy();
          console.error("response exceeds frame limit");
          process.exit(1);
        }
      });
      socket.on("end", () => {
        clearTimeout(timer);
        const response = JSON.parse(output) as Dict;
        if (response.error) {
          console.error(String(response.error));
          process.exit(1);
        }
        console.log(JSON.stringify(response));
      });
      socket.on("error", (error) => {
        console.error(error.message);
        process.exit(1);
      });
    }
  }
}
