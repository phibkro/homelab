import { afterAll, expect, test } from "bun:test";
import { type ChildProcess, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { once } from "node:events";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const launcher = join(import.meta.dir, "firecracker-environment-launcher.ts");
const stateRoot = mkdtempSync(join(tmpdir(), "adlc-launcher-test-"));
const runner = join(stateRoot, "run-launcher.ts");
const generation = { generationId: "shg_demo", ordinal: 1 };
const artifactRoot = join(stateRoot, "artifacts");
mkdirSync(artifactRoot, { recursive: true });
const writeArtifact = (name: string, contents: string) => {
  const path = join(artifactRoot, name);
  writeFileSync(path, contents);
  return path;
};
const artifacts = {
  firecracker: writeArtifact("firecracker", "firecracker"),
  jailer: writeArtifact("jailer", "jailer"),
  kernel: writeArtifact("kernel", "kernel"),
  initrd: writeArtifact("initrd", "initrd"),
  store: writeArtifact("store", "store"),
};
const sha256 = (value: string) => `sha256:${createHash("sha256").update(value).digest("hex")}`;
const resources = {
  cpuMaxMicros: 100_000,
  cpuWeight: 100,
  memoryHighBytes: 128 * 1024 * 1024,
  memoryMaxBytes: 256 * 1024 * 1024,
  vmmProcessTreePidsMax: 16,
  stateVolumeBytes: 4 * 1024 * 1024,
  ioMaxBytesPerSecond: 1024,
};
const materializerEnvironment = {
  ADLC_FIRECRACKER: artifacts.firecracker,
  ADLC_JAILER: artifacts.jailer,
  ADLC_GUEST_KERNEL: artifacts.kernel,
  ADLC_GUEST_INITRD: artifacts.initrd,
  ADLC_GUEST_STORE: artifacts.store,
  ADLC_GUEST_BOOT_ARGS: "console=ttyS0",
};
const materializeRequest = (environmentId: string) => ({
  action: "materialize",
  generation,
  spec: {
    _tag: "SelfHostedEnvironmentSpec",
    environmentId,
    organizationId: "organization:demo",
    projectId: "prj_demo",
    workId: "tsk_demo",
    actorId: "worker:demo",
    sessionId: "ses_demo",
    policy: { net: "off" },
    policyDigest: sha256("policy"),
    guestKernelDigest: sha256("kernel"),
    guestInitrdDigest: sha256("initrd"),
    guestStoreDigest: sha256("store"),
    stateVolumeTemplateDigest: sha256(
      JSON.stringify({ fsType: "ext4", sizeBytes: resources.stateVolumeBytes }),
    ),
    harnessDigest: sha256("harness"),
    profileDigest: sha256("profile"),
    capabilityManifestDigest: sha256("capabilities"),
    networkMode: "off",
    resources,
    specificationDigest: sha256("specification"),
  },
});

writeFileSync(
  runner,
  `import { readFileSync } from "node:fs";
import { runLauncherAction } from ${JSON.stringify(launcher)};

try {
  console.log(JSON.stringify(await runLauncherAction(JSON.parse(readFileSync(0, "utf8")))));
} catch (error) {
  console.error(error instanceof Error ? error.message : "launcher failure");
  process.exitCode = 1;
}
`,
);

const request = (
  action: "observe" | "probe" | "drain" | "stop" | "reconcile" | "destroy",
  environmentId: string,
  ordinal = 1,
) => ({
  action,
  environmentId,
  generation: { generationId: generation.generationId, ordinal },
});
const state = (environmentId: string, overrides: Record<string, unknown> = {}) => ({
  environmentId,
  generation,
  pid: 0,
  pidStartTime: "",
  pidCgroup: "",
  pidNetns: "",
  pidExe: "",
  netns: "",
  cgroupPath: "",
  jailerPid: 0,
  jailerStartTime: "",
  jailerExe: "",
  netnsPid: 0,
  netnsStartTime: "",
  netnsExe: "",
  draining: false,
  receipt: null,
  ...overrides,
});
const writeState = (environmentId: string, value: Record<string, unknown>) => {
  const directory = join(stateRoot, environmentId, generation.generationId);
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, "state.json"), JSON.stringify(value));
};
const runLauncher = async (
  value: Record<string, unknown>,
  environment: Record<string, string> = {},
) => {
  const child = Bun.spawn([process.execPath, runner], {
    stdin: new Blob([JSON.stringify(value)]),
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, ADLC_STATE_ROOT: stateRoot, ...environment },
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  return { exitCode, stdout, stderr };
};
const liveProcess = () => {
  const child = spawn("sleep", ["60"], { stdio: "ignore" });
  if (!child.pid) throw new Error("test process did not start");
  process.kill(child.pid, 0);
  return child;
};
const stopProcess = async (child: ChildProcess) => {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await once(child, "exit");
};
const stateWithLiveVmm = (environmentId: string, child: ChildProcess) => {
  const pid = child.pid;
  if (!pid) throw new Error("test process did not have a pid");
  const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
  return state(environmentId, {
    pid,
    pidStartTime: stat.slice(stat.lastIndexOf(")") + 2).split(" ")[19],
    pidCgroup: readFileSync(`/proc/${pid}/cgroup`, "utf8").trim(),
    pidNetns: readlinkSync(`/proc/${pid}/ns/net`),
    pidExe: readlinkSync(`/proc/${pid}/exe`),
  });
};

afterAll(() => rmSync(stateRoot, { recursive: true, force: true }));
test("reconcile reports absent without creating generation state", async () => {
  const environmentId = `reconcile-absent-${process.pid}`;

  const result = await runLauncher(request("reconcile", environmentId));

  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual({ _tag: "SelfHostedGenerationAbsent" });
});

test("reconcile reports a recorded non-live VMM as dead", async () => {
  const environmentId = `reconcile-dead-${process.pid}`;
  writeState(environmentId, state(environmentId));

  const result = await runLauncher(request("reconcile", environmentId));

  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual({ _tag: "SelfHostedGenerationDead" });
});

test("reconcile reports a live generation without a receipt as not ready", async () => {
  const child = liveProcess();
  const environmentId = `reconcile-unready-${process.pid}`;
  try {
    writeState(environmentId, stateWithLiveVmm(environmentId, child));

    const result = await runLauncher(request("reconcile", environmentId));

    expect(result.exitCode).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual({ _tag: "SelfHostedGenerationNotReady" });
  } finally {
    await stopProcess(child);
  }
});

test("reconcile fails closed on a raw-live VMM identity mismatch", async () => {
  const child = liveProcess();
  const environmentId = `reconcile-mismatch-${process.pid}`;
  try {
    writeState(
      environmentId,
      state(environmentId, {
        pid: child.pid,
        pidStartTime: "mismatched-start-time",
        pidCgroup: "mismatched-cgroup",
        pidNetns: "mismatched-netns",
        pidExe: "mismatched-exe",
      }),
    );

    const result = await runLauncher(request("reconcile", environmentId));

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded VMM process identity mismatch");
  } finally {
    await stopProcess(child);
  }
});

test("materialize preserves a raw-live mismatched VMM generation root", async () => {
  const child = liveProcess();
  const environmentId = `materialize-mismatch-${process.pid}`;
  const directory = join(stateRoot, environmentId, generation.generationId);
  try {
    writeState(
      environmentId,
      state(environmentId, {
        pid: child.pid,
        pidStartTime: "mismatched-start-time",
        pidCgroup: "mismatched-cgroup",
        pidNetns: "mismatched-netns",
        pidExe: "mismatched-exe",
      }),
    );
    writeFileSync(join(directory, "preserve"), "mismatch");
    const before = readFileSync(join(directory, "state.json"), "utf8");

    const result = await runLauncher(materializeRequest(environmentId), materializerEnvironment);

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded VMM process identity mismatch");
    expect(readFileSync(join(directory, "state.json"), "utf8")).toBe(before);
    expect(readFileSync(join(directory, "preserve"), "utf8")).toBe("mismatch");
    expect(() => process.kill(child.pid!, 0)).not.toThrow();
  } finally {
    await stopProcess(child);
  }
});
test("materialize preserves a raw-live mismatched keeper generation root", async () => {
  const child = liveProcess();
  const environmentId = `materialize-keeper-${process.pid}`;
  const directory = join(stateRoot, environmentId, generation.generationId);
  try {
    writeState(
      environmentId,
      state(environmentId, {
        netnsPid: child.pid,
        netnsStartTime: "mismatched-start-time",
        netnsExe: "mismatched-exe",
      }),
    );
    writeFileSync(join(directory, "preserve"), "keeper");
    const before = readFileSync(join(directory, "state.json"), "utf8");

    const result = await runLauncher(materializeRequest(environmentId), materializerEnvironment);

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded netns keeper identity mismatch");
    expect(readFileSync(join(directory, "state.json"), "utf8")).toBe(before);
    expect(readFileSync(join(directory, "preserve"), "utf8")).toBe("keeper");
    expect(() => process.kill(child.pid!, 0)).not.toThrow();
  } finally {
    await stopProcess(child);
  }
});

test("materialize never replaces a verified live VMM generation root", async () => {
  const child = liveProcess();
  const environmentId = `materialize-live-${process.pid}`;
  const directory = join(stateRoot, environmentId, generation.generationId);
  try {
    writeState(environmentId, stateWithLiveVmm(environmentId, child));
    writeFileSync(join(directory, "preserve"), "live");
    const before = readFileSync(join(directory, "state.json"), "utf8");

    const result = await runLauncher(materializeRequest(environmentId), materializerEnvironment);

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("refusing materialization replacement for a verified live VMM");
    expect(readFileSync(join(directory, "state.json"), "utf8")).toBe(before);
    expect(readFileSync(join(directory, "preserve"), "utf8")).toBe("live");
    expect(() => process.kill(child.pid!, 0)).not.toThrow();
  } finally {
    await stopProcess(child);
  }
});

test("observe rejects a raw-live VMM process with mismatched identity", async () => {
  const child = liveProcess();
  const environmentId = `observe-vmm-${process.pid}`;
  try {
    writeState(
      environmentId,
      state(environmentId, {
        pid: child.pid,
        pidStartTime: "mismatched-start-time",
        pidCgroup: "mismatched-cgroup",
        pidNetns: "mismatched-netns",
        pidExe: "mismatched-exe",
      }),
    );

    const result = await runLauncher(request("observe", environmentId));

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded VMM process identity mismatch");
  } finally {
    await stopProcess(child);
  }
});

test("stop rejects a raw-live VMM process with mismatched identity", async () => {
  const child = liveProcess();
  const environmentId = `stop-vmm-${process.pid}`;
  try {
    writeState(
      environmentId,
      state(environmentId, {
        pid: child.pid,
        pidStartTime: "mismatched-start-time",
        pidCgroup: "mismatched-cgroup",
        pidNetns: "mismatched-netns",
        pidExe: "mismatched-exe",
      }),
    );

    const result = await runLauncher(request("stop", environmentId));

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded VMM process identity mismatch");
    expect(() => process.kill(child.pid!, 0)).not.toThrow();
  } finally {
    await stopProcess(child);
  }
});

test("observe rejects a raw-live netns keeper with mismatched identity", async () => {
  const child = liveProcess();
  const environmentId = `observe-netns-${process.pid}`;
  try {
    writeState(
      environmentId,
      state(environmentId, {
        netnsPid: child.pid,
        netnsStartTime: "mismatched-start-time",
        netnsExe: "mismatched-exe",
      }),
    );

    const result = await runLauncher(request("observe", environmentId));

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded netns keeper identity mismatch");
  } finally {
    await stopProcess(child);
  }
});

test("stop rejects a raw-live netns keeper with mismatched identity", async () => {
  const child = liveProcess();
  const environmentId = `stop-netns-${process.pid}`;
  try {
    writeState(
      environmentId,
      state(environmentId, {
        netnsPid: child.pid,
        netnsStartTime: "mismatched-start-time",
        netnsExe: "mismatched-exe",
      }),
    );

    const result = await runLauncher(request("stop", environmentId));

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("recorded netns keeper identity mismatch");
    expect(() => process.kill(child.pid!, 0)).not.toThrow();
  } finally {
    await stopProcess(child);
  }
});

for (const action of ["observe", "probe", "drain", "stop"] as const) {
  test(`${action} rejects a request with the wrong generation ordinal`, async () => {
    const environmentId = `wrong-ordinal-${action}-${process.pid}`;
    writeState(environmentId, state(environmentId));

    const result = await runLauncher(request(action, environmentId, 2));

    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("generation binding mismatch");
    if (action === "drain") {
      const persisted = JSON.parse(
        readFileSync(join(stateRoot, environmentId, generation.generationId, "state.json"), "utf8"),
      ) as Record<string, unknown>;
      expect(persisted.draining).toBe(false);
    }
  });
}

test("destroy removes an incomplete generation with placeholder process ids", async () => {
  const environmentId = `destroy-incomplete-${process.pid}`;
  writeState(environmentId, state(environmentId));

  const result = await runLauncher(request("destroy", environmentId));

  expect(result.exitCode).toBe(0);
  expect(existsSync(join(stateRoot, environmentId, generation.generationId))).toBe(false);
});

test("destroy rejects a request with the wrong generation ordinal", async () => {
  const environmentId = `wrong-ordinal-destroy-${process.pid}`;
  writeState(environmentId, state(environmentId));

  const result = await runLauncher(request("destroy", environmentId, 2));

  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("generation binding mismatch");
  expect(existsSync(join(stateRoot, environmentId, generation.generationId, "state.json"))).toBe(
    true,
  );
});
