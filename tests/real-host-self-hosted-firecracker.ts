import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { Database } from "bun:sqlite";
import {
  accessSync,
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

const launcherName = "agent-engine-self-hosted-launcher";
const stateVolumeBytes = 256 * 1024 * 1024;
const policyDigest = "sha256:9defe902930f3e13382614f7cf2b838b4fd2f376b082e64f89773a765d29c465";
const digest = (bytes: Uint8Array) => `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
const artifactDigest = (path: string) =>
  `sha256:${execFileSync("sha256sum", ["--", path], { encoding: "utf8" }).split(/\s+/, 1)[0]}`;
const stateTemplateDigest = digest(
  Buffer.from(JSON.stringify({ fsType: "ext4", sizeBytes: stateVolumeBytes })),
);

interface CommandResult {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

interface ControllerResult extends CommandResult {
  readonly response: Record<string, unknown>;
}

interface LauncherRuntime {
  readonly executable: string;
  readonly environment: Record<string, string>;
  readonly delegatedCgroup?: string;
  readonly cleanup: () => Promise<void>;
}

const fail = (message: string): never => {
  throw new Error(message);
};
const assert = (condition: unknown, message: string): asserts condition => {
  if (!condition) fail(message);
};
const quoted = (value: string) => `'${value.replaceAll("'", "'\\''")}'`;

const run = async (
  command: readonly string[],
  options: {
    readonly cwd?: string;
    readonly env?: Record<string, string | undefined>;
    readonly stdin?: string;
    readonly timeoutMs?: number;
  } = {},
): Promise<CommandResult> => {
  const child = Bun.spawn(command, {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    stdin: options.stdin === undefined ? "ignore" : new Blob([options.stdin]),
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = new Response(child.stdout).text();
  const stderr = new Response(child.stderr).text();
  const timeoutMs = options.timeoutMs ?? 120_000;
  const timeout = Promise.withResolvers<never>();
  const timer = setTimeout(() => {
    child.kill();
    timeout.reject(new Error(`${command[0]} timed out after ${String(timeoutMs)}ms`));
  }, timeoutMs);
  try {
    const exitCode = await Promise.race([child.exited, timeout.promise]);
    return { exitCode, stdout: await stdout, stderr: await stderr };
  } finally {
    clearTimeout(timer);
  }
};

const required = (result: CommandResult, description: string): CommandResult => {
  if (result.exitCode !== 0)
    fail(`${description}: ${result.stderr.trim() || result.stdout.trim()}`);
  return result;
};
const sudo = async (arguments_: readonly string[], description: string) =>
  required(await run(["sudo", "--", ...arguments_], { timeoutMs: 180_000 }), description);
const rootText = async (path: string) => (await sudo(["cat", path], `read ${path}`)).stdout;
const rootExists = async (path: string) =>
  (await run(["sudo", "--", "test", "-e", path])).exitCode === 0;
const rootAbsent = async (path: string) =>
  assert(!(await rootExists(path)), `residual path remains: ${path}`);

const exported = (wrapper: string, key: string): string => {
  const source = readFileSync(wrapper, "utf8");
  const match = new RegExp(`^export ${key}=(?:'([^']+)'|([^\\n]+))$`, "m").exec(source);
  const value = match?.[1] ?? match?.[2];
  if (!value) fail(`launcher wrapper does not export ${key}`);
  return value;
};
const launcherScript = (wrapper: string): { readonly bun: string; readonly script: string } => {
  const source = readFileSync(wrapper, "utf8");
  const match = /^exec (\/nix\/store\/[^ ]+) (\/nix\/store\/[^ ]+) "\$@"$/m.exec(source);
  if (!match?.[1] || !match[2]) fail("launcher wrapper does not contain its immutable entrypoint");
  return { bun: match[1], script: match[2] };
};
const wrapperEnvironment = (wrapper: string) => ({
  PATH: exported(wrapper, "PATH").replace("$PATH", process.env.PATH ?? ""),
  ADLC_FIRECRACKER: exported(wrapper, "ADLC_FIRECRACKER"),
  ADLC_JAILER: exported(wrapper, "ADLC_JAILER"),
  ADLC_GUEST_KERNEL: exported(wrapper, "ADLC_GUEST_KERNEL"),
  ADLC_GUEST_INITRD: exported(wrapper, "ADLC_GUEST_INITRD"),
  ADLC_GUEST_STORE: exported(wrapper, "ADLC_GUEST_STORE"),
  ADLC_GUEST_BOOT_ARGS: exported(wrapper, "ADLC_GUEST_BOOT_ARGS"),
  ADLC_GUEST_UID: exported(wrapper, "ADLC_GUEST_UID"),
  ADLC_GUEST_GID: exported(wrapper, "ADLC_GUEST_GID"),
});
const unifiedCgroupPath = (membership: string) => {
  const hierarchy = membership
    .trim()
    .split("\n")
    .find((entry) => entry.startsWith("0::"));
  if (!hierarchy) fail("missing unified cgroup membership");
  const path = hierarchy.slice(3);
  if (!path.startsWith("/")) fail("invalid unified cgroup membership");
  return path;
};
const projectSource = async (sourceRoot: string): Promise<string> => {
  const projection = mkdtempSync(join(tmpdir(), "adlc-homelab-source-"));
  try {
    const files = required(
      await run(["git", "-C", sourceRoot, "ls-files", "-co", "--exclude-standard", "-z"]),
      "list current homelab source files",
    ).stdout.split("\0");
    for (const relativePath of files) {
      if (!relativePath || relativePath === ".git" || relativePath.startsWith(".worktrees/"))
        continue;
      const source = resolve(sourceRoot, relativePath);
      if (!source.startsWith(`${sourceRoot}/`))
        fail(`source projection escapes checkout: ${relativePath}`);
      if (!existsSync(source)) continue;
      const target = join(projection, relativePath);
      mkdirSync(dirname(target), { recursive: true });
      cpSync(source, target, { dereference: false, recursive: true });
    }
    return projection;
  } catch (error) {
    rmSync(projection, { recursive: true, force: true });
    throw error;
  }
};

const transientLauncher = async (directory: string): Promise<LauncherRuntime> => {
  const sourceRoot = resolve(import.meta.dir, "..");
  const projection = await projectSource(sourceRoot);
  const build = await (async () => {
    try {
      return required(
        await run(
          [
            "nix",
            "build",
            "--no-link",
            "--print-out-paths",
            `path:${projection}#nixosConfigurations.workstation.config.system.build.toplevel`,
          ],
          { cwd: projection, timeoutMs: 900_000 },
        ),
        "build current workstation toplevel",
      );
    } finally {
      rmSync(projection, { recursive: true, force: true });
    }
  })();
  const toplevel = build.stdout.trim();
  assert(toplevel.startsWith("/nix/store/"), "Nix did not report a workstation toplevel");
  const wrapper = join(toplevel, "sw/bin", launcherName);
  assert(existsSync(wrapper), "built workstation toplevel lacks the launcher");
  const entrypoint = launcherScript(wrapper);
  const stateRoot = `/var/lib/adlc-firecracker-transient-${process.pid}`;
  const runtimeRoot = `/run/adlc-firecracker-transient-${process.pid}`;
  const socket = join(runtimeRoot, "launcher.sock");
  const unit = `adlc-firecracker-transient-${process.pid}.service`;
  const failureLogRoot = join(directory, "failure-logs");
  const socketGid = String(process.getgid?.() ?? 0);
  const environment = {
    ...wrapperEnvironment(wrapper),
    ADLC_STATE_ROOT: stateRoot,
    ADLC_SOCKET: socket,
    ADLC_SOCKET_GID: socketGid,
    ADLC_FAILURE_LOG_ROOT: failureLogRoot,
  };
  await sudo(["install", "-d", "-m", "0700", stateRoot], "create transient state root");
  await sudo(["install", "-d", "-m", "0755", failureLogRoot], "create transient failure-log root");
  await sudo(
    ["install", "-d", "-m", "0710", "-g", socketGid, runtimeRoot],
    "create transient runtime root",
  );
  const properties = [
    "Slice=adlc-firecracker.slice",
    "Delegate=cpu io memory pids",
    "DelegateSubgroup=launcher",
    "TasksAccounting=yes",
    "CPUQuota=100%",
    "CPUWeight=100",
    "MemoryHigh=2G",
    "MemoryMax=4G",
    "TasksMax=256",
    "LimitNOFILE=1024",
    "NoNewPrivileges=false",
    "ProtectHome=true",
    "ProtectSystem=strict",
    `ReadWritePaths=${stateRoot} ${runtimeRoot} ${failureLogRoot}`,
  ];
  const daemon = await run(
    [
      "sudo",
      "--",
      "systemd-run",
      `--unit=${unit}`,
      "--collect",
      "--service-type=exec",
      ...properties.flatMap((property) => [`--property=${property}`]),
      ...Object.entries(environment).flatMap(([key, value]) => [`--setenv=${key}=${value}`]),
      entrypoint.bun,
      entrypoint.script,
      "--daemon",
    ],
    { timeoutMs: 60_000 },
  );
  required(daemon, "start transient launcher daemon");
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (existsSync(socket)) break;
    await Bun.sleep(100);
  }
  assert(existsSync(socket), "transient launcher socket did not appear");
  accessSync(socket, 2);
  const unitCgroup = required(
    await run(["sudo", "--", "systemctl", "show", unit, "--property=ControlGroup", "--value"]),
    "read transient launcher cgroup",
  ).stdout.trim();
  assert(unitCgroup.startsWith("/"), "transient launcher does not have a cgroup");
  const mainPid = required(
    await run(["sudo", "--", "systemctl", "show", unit, "--property=MainPID", "--value"]),
    "read transient launcher main PID",
  ).stdout.trim();
  assert(/^[1-9][0-9]*$/.test(mainPid), "transient launcher does not have a main PID");
  assert(
    unifiedCgroupPath(await rootText(`/proc/${mainPid}/cgroup`)) === `${unitCgroup}/launcher`,
    "transient launcher daemon is not in its delegated leaf subgroup",
  );
  const client = join(directory, launcherName);
  writeFileSync(
    client,
    `#!/bin/sh\nexec env ${Object.entries(environment)
      .map(([key, value]) => `${key}=${quoted(value)}`)
      .join(" ")} ${quoted(entrypoint.bun)} ${quoted(entrypoint.script)} "$@"\n`,
  );
  chmodSync(client, 0o755);
  return {
    executable: client,
    delegatedCgroup: `/sys/fs/cgroup${unitCgroup}`,
    environment,
    cleanup: async () => {
      const log = await run(["sudo", "--", "journalctl", "--no-pager", "-u", unit, "-n", "80"]);
      if (log.stdout.trim()) console.error(log.stdout.trim());
      await run(["sudo", "--", "systemctl", "stop", unit]);
      await sudo(["rm", "-rf", stateRoot, runtimeRoot], "remove transient launcher state");
    },
  };
};

const installedLauncher = (): LauncherRuntime => {
  const executable = Bun.which(launcherName);
  assert(executable, `${launcherName} is unavailable on PATH`);
  assert(existsSync("/run/adlc-firecracker/launcher.sock"), "launcher socket is unavailable");
  accessSync("/run/adlc-firecracker/launcher.sock", 2);
  const wrapper = resolve(executable);
  return { executable, environment: wrapperEnvironment(wrapper), cleanup: async () => {} };
};

const seedPolicy = async (databasePath: string, repositoryRoot: string, seedPath: string) => {
  writeFileSync(
    seedPath,
    `import * as Effect from "effect/Effect"; import * as Layer from "effect/Layer"; import { CapacityPolicyIdSchema, ProjectIdSchema, TimestampSchema } from "@work-engine/protocol"; import { FleetCompletionAuthority, FleetScheduler, FleetSchedulerCapabilities, FleetSchedulerLive, FleetSchedulerStore } from "@work-engine/runtime"; import { makeSqliteFleetSchedulerStore } from "@work-engine/self-hosted-environment"; const store = makeSqliteFleetSchedulerStore(process.env.ADLC_REAL_HOST_DATABASE!); const dependencies = Layer.mergeAll(Layer.succeed(FleetSchedulerStore, store), Layer.succeed(FleetSchedulerCapabilities, { now: Effect.sync(() => TimestampSchema.make("2026-09-12T00:00:00.000Z")), newId: (prefix: string) => prefix + globalThis.crypto.randomUUID() }), Layer.succeed(FleetCompletionAuthority, { snapshotTriple: () => Effect.as(Effect.void, undefined) })); try { await Effect.runPromise(Effect.gen(function* () { const scheduler = yield* FleetScheduler; yield* scheduler.setPolicy({ _tag: "CapacityPolicy", policyId: CapacityPolicyIdSchema.make("cap_00000000-0000-4000-8000-000000000001"), organizationId: "organization:default", projectId: ProjectIdSchema.make("prj_00000000-0000-4000-8000-000000000001"), revision: 1, maxConcurrentEnvironments: 1, organizationMaxConcurrentEnvironments: 1, costBudgetMicros: 1_000_000, currency: "usd", activatedAt: TimestampSchema.make("2026-09-12T00:00:00.000Z") }); }).pipe(Effect.provide(FleetSchedulerLive.pipe(Layer.provide(dependencies))))); } finally { store.close(); }`,
  );
  required(
    await run([process.execPath, seedPath], {
      cwd: repositoryRoot,
      env: { ADLC_REAL_HOST_DATABASE: databasePath },
    }),
    "seed FleetScheduler policy",
  );
};

const runController = async (
  repositoryRoot: string,
  controller: string,
  databasePath: string,
  launcherDirectory: string,
  command: Record<string, unknown>,
): Promise<ControllerResult> => {
  const result = await run([process.execPath, controller, "--database", databasePath], {
    cwd: repositoryRoot,
    env: { PATH: `${launcherDirectory}:${process.env.PATH ?? ""}` },
    stdin: JSON.stringify(command),
    timeoutMs: 180_000,
  });
  let response: Record<string, unknown>;
  try {
    response = JSON.parse(result.stdout) as Record<string, unknown>;
  } catch (error) {
    fail(
      `controller did not produce JSON (${error instanceof Error ? error.message : "unknown error"}; ${String(result.stdout.length)} bytes; tail=${JSON.stringify(result.stdout.slice(-512))}): ${result.stderr.trim()} ${result.stdout.trim()}`,
    );
  }
  return { ...result, response };
};
const successful = (result: ControllerResult, command: string): Record<string, unknown> => {
  assert(result.exitCode === 0, `${command} failed: ${JSON.stringify(result.response)}`);
  assert(result.response.command === command, `${command} returned the wrong response tag`);
  return result.response;
};
const runLauncher = async (
  runtime: LauncherRuntime,
  request: Record<string, unknown>,
): Promise<CommandResult> =>
  run([runtime.executable], {
    env: runtime.environment,
    stdin: `${JSON.stringify(request)}\n`,
    timeoutMs: 30_000,
  });

const recordState = async (
  stateRoot: string,
  environmentId: string,
  generation: Record<string, unknown>,
) => {
  const generationId = String(generation.generationId);
  const base = join(stateRoot, environmentId, generationId);
  return {
    base,
    state: JSON.parse(await rootText(join(base, "state.json"))) as Record<string, unknown>,
  };
};
const forceMaterializingCheckpoint = (databasePath: string, environmentId: string): void => {
  const database = new Database(databasePath);
  try {
    const row = database
      .query(
        `SELECT revision, record_json
         FROM self_hosted_environment_records
         WHERE environment_id = ?`,
      )
      .get(environmentId) as { readonly revision: number; readonly record_json: string } | null;
    assert(row !== null, "missing Environment record for Materializing replay checkpoint");
    const record = JSON.parse(row.record_json) as Record<string, unknown>;
    assert(record.lifecycle === "Ready", "replay checkpoint must start with a Ready Environment");
    record.lifecycle = "Materializing";
    const result = database
      .query(
        `UPDATE self_hosted_environment_records
         SET record_json = ?
         WHERE environment_id = ? AND revision = ?`,
      )
      .run(JSON.stringify(record), environmentId, row.revision);
    assert(result.changes === 1, "failed to persist Materializing replay checkpoint");
  } finally {
    database.close();
  }
};
const schedulerAllocationCount = (databasePath: string): number => {
  const database = new Database(databasePath);
  try {
    const row = database
      .query(`SELECT state_json FROM local_fleet_scheduler_state WHERE singleton = 1`)
      .get() as { readonly state_json: string } | null;
    assert(row !== null, "missing FleetScheduler state");
    const state = JSON.parse(row.state_json) as { readonly allocations: Record<string, unknown> };
    return Object.keys(state.allocations).length;
  } finally {
    database.close();
  }
};
const assertCgroup = async (receipt: Record<string, unknown>, delegatedCgroup?: string) => {
  const cgroup = String(receipt.cgroupPath);
  if (delegatedCgroup) {
    assert(
      cgroup.startsWith(`${delegatedCgroup}/`),
      `VMM cgroup escaped delegated service subtree: ${cgroup}`,
    );
    const enabled = (await rootText(join(delegatedCgroup, "cgroup.subtree_control")))
      .trim()
      .split(/\s+/);
    for (const controller of ["cpu", "io", "memory", "pids"])
      assert(enabled.includes(controller), `delegated cgroup did not enable ${controller}`);
  }
  const controls = receipt.cgroupControls as Record<string, unknown>;
  const names = {
    cpuMax: "cpu.max",
    cpuWeight: "cpu.weight",
    memoryHigh: "memory.high",
    memoryMax: "memory.max",
    pidsMax: "pids.max",
    ioMax: "io.max",
  };
  for (const [key, file] of Object.entries(names))
    assert(
      (await rootText(join(cgroup, file))).trim() === controls[key],
      `cgroup ${file} differs from receipt`,
    );
};
const assertNetns = async (pid: number) => {
  const links = JSON.parse(
    required(
      await run(["sudo", "--", "nsenter", "-t", String(pid), "-n", "ip", "-j", "link", "show"]),
      "read VMM netns links",
    ).stdout,
  ) as Array<Record<string, unknown>>;
  const addresses = JSON.parse(
    required(
      await run(["sudo", "--", "nsenter", "-t", String(pid), "-n", "ip", "-j", "address", "show"]),
      "read VMM netns addresses",
    ).stdout,
  ) as Array<Record<string, unknown>>;
  const routes = JSON.parse(
    required(
      await run([
        "sudo",
        "--",
        "nsenter",
        "-t",
        String(pid),
        "-n",
        "ip",
        "-j",
        "route",
        "show",
        "table",
        "all",
      ]),
      "read VMM netns routes",
    ).stdout,
  ) as Array<Record<string, unknown>>;
  assert(links.length === 1 && links[0]?.ifname === "lo", "VMM netns has a non-loopback interface");
  assert(
    !addresses.some((entry) =>
      (entry.addr_info as Array<Record<string, unknown>> | undefined)?.some(
        (address) =>
          !(
            (address.family === "inet" && address.local === "127.0.0.1") ||
            (address.family === "inet6" && address.local === "::1")
          ),
      ),
    ),
    "VMM netns has a non-loopback address",
  );
  assert(!routes.some((route) => route.dev !== "lo"), "VMM netns has an external route");
};
const assertFirecrackerConfig = async (base: string) => {
  const configPath = join(base, "jailer", "firecracker");
  const roots = (
    await sudo(["find", configPath, "-name", "config.json", "-print"], "locate Firecracker config")
  ).stdout
    .trim()
    .split("\n");
  assert(roots.length === 1 && roots[0], "expected one Firecracker config");
  const config = JSON.parse(await rootText(roots[0])) as Record<string, unknown>;
  assert(
    Array.isArray(config["network-interfaces"]) && config["network-interfaces"].length === 0,
    "Firecracker config has a network device",
  );
  const hostPaths = JSON.stringify({
    kernel: (config["boot-source"] as Record<string, unknown>).kernel_image_path,
    initrd: (config["boot-source"] as Record<string, unknown>).initrd_path,
    drives: (config.drives as Array<Record<string, unknown>>).map((drive) => drive.path_on_host),
    vsock: (config.vsock as Record<string, unknown>).uds_path,
  });
  for (const forbidden of [
    "/home/",
    "/run/secrets",
    "launcher.sock",
    "/srv/share/projects",
    "/nix/store/",
  ])
    assert(!hostPaths.includes(forbidden), `Firecracker config exposes host path ${forbidden}`);
};

const repositoryRoot = process.env.ADLC_REPOSITORY_ROOT;
assert(repositoryRoot, "ADLC_REPOSITORY_ROOT must name the adlc-os checkout");
const adlcRoot = resolve(repositoryRoot);
const controller = join(adlcRoot, "apps/local-environment-controller/src/main.ts");
assert(existsSync(controller), `controller entrypoint is unavailable: ${controller}`);
assert(process.getuid?.() !== 0, "run this journey as the unprivileged launcher client, not root");
assert(existsSync("/dev/kvm"), "/dev/kvm is unavailable to the root launcher daemon");
const directory = mkdtempSync(join(tmpdir(), "adlc-real-host-"));
const databasePath = join(directory, "controller.sqlite");
const seedPath = join(adlcRoot, `.adlc-real-host-seed-${process.pid}.ts`);
const environmentId = `self-hosted-real-${process.pid}`;
const mode = process.env.ADLC_REAL_HOST_MODE ?? "installed";
let runtime: LauncherRuntime | undefined;
let created = false;

const createOnly = process.env.ADLC_REAL_HOST_CREATE_ONLY === "1";
try {
  runtime = mode === "transient" ? await transientLauncher(directory) : installedLauncher();
  const kernel = runtime.environment.ADLC_GUEST_KERNEL;
  const initrd = runtime.environment.ADLC_GUEST_INITRD;
  const store = runtime.environment.ADLC_GUEST_STORE;
  const stateRoot = runtime.environment.ADLC_STATE_ROOT ?? "/var/lib/adlc-firecracker";
  for (const artifact of [kernel, initrd, store])
    assert(existsSync(artifact), `launcher artifact is unavailable: ${artifact}`);
  await seedPolicy(databasePath, adlcRoot, seedPath);
  const createCommand = {
    command: "create",
    request: {
      _tag: "CreateSelfHostedEnvironment",
      requestId: "adm_00000000-0000-4000-8000-000000000001",
      spec: {
        _tag: "SelfHostedEnvironmentSpec",
        environmentId,
        organizationId: "organization:default",
        projectId: "prj_00000000-0000-4000-8000-000000000001",
        workId: "tsk_00000000-0000-4000-8000-000000000001",
        actorId: "worker:real-host",
        sessionId: "ses_00000000-0000-4000-8000-000000000001",
        policy: { net: "off" },
        policyDigest,
        guestKernelDigest: artifactDigest(kernel),
        guestInitrdDigest: artifactDigest(initrd),
        guestStoreDigest: artifactDigest(store),
        stateVolumeTemplateDigest: stateTemplateDigest,
        harnessDigest: digest(Buffer.from("real-host-journey")),
        profileDigest: digest(Buffer.from("omp-rpc-get-state")),
        capabilityManifestDigest: digest(Buffer.from("omp.get_state")),
        networkMode: "off",
        resources: {
          cpuMaxMicros: 1_000_000,
          cpuWeight: 100,
          memoryHighBytes: 512 * 1024 * 1024,
          memoryMaxBytes: 1024 * 1024 * 1024,
          vmmProcessTreePidsMax: 128,
          stateVolumeBytes,
          ioMaxBytesPerSecond: 10 * 1024 * 1024,
        },
      },
    },
  };
  const create = successful(
    await runController(adlcRoot, controller, databasePath, directory, createCommand),
    "create",
  );
  created = true;
  const record = create.record as Record<string, unknown>;
  const generation = record.activeGeneration as Record<string, unknown>;
  const receipt = (record.materializationReceipts as readonly Record<string, unknown>[])[0];
  assert(
    record.lifecycle === "Ready" && generation?.ordinal === 1 && receipt,
    "create did not persist Ready generation 1 with receipt",
  );
  assert(
    receipt.networkDevicePresent === false &&
      receipt.metadataServicePresent === false &&
      receipt.ompReadinessProbeSucceeded === true,
    "receipt lacks net-off readiness proof",
  );
  assert(
    receipt.vsockCid === 3 && receipt.vsockPort === 5000,
    "receipt has the wrong vsock binding",
  );
  const first = await recordState(stateRoot, environmentId, generation);
  await assertCgroup(receipt, runtime.delegatedCgroup);
  await assertNetns(Number(first.state.pid));
  await assertFirecrackerConfig(first.base);

  if (createOnly) {
    console.log(
      JSON.stringify({ status: "passed", mode, phase: "create", environmentId, generation }),
    );
  } else {
    const observed = successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "recover",
        environmentId,
      }),
      "recover",
    );
    assert(
      ((observed.record as Record<string, unknown>).activeGeneration as Record<string, unknown>)
        .ordinal === 1,
      "live recover made an unsafe generation",
    );
    const allocationsBeforeReplay = schedulerAllocationCount(databasePath);
    forceMaterializingCheckpoint(databasePath, environmentId);
    const replayed = successful(
      await runController(adlcRoot, controller, databasePath, directory, createCommand),
      "create",
    );
    const replayedRecord = replayed.record as Record<string, unknown>;
    const replayedGeneration = replayedRecord.activeGeneration as Record<string, unknown>;
    const replayedReceipt = (
      replayedRecord.materializationReceipts as readonly Record<string, unknown>[]
    ).at(-1);
    const replayedState = await recordState(stateRoot, environmentId, replayedGeneration);
    assert(
      replayedRecord.lifecycle === "Ready" &&
        replayedGeneration.generationId === generation.generationId &&
        replayedGeneration.ordinal === 1 &&
        (replayedRecord.materializationReceipts as readonly unknown[]).length === 1 &&
        replayedReceipt?.specificationDigest === receipt.specificationDigest &&
        replayedState.state.pid === first.state.pid,
      "exact create replay did not reconcile the live assigned generation",
    );
    assert(
      allocationsBeforeReplay === 1 &&
        schedulerAllocationCount(databasePath) === allocationsBeforeReplay,
      "exact create replay made another scheduler allocation",
    );
    const inspected = successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "inspect",
        environmentId,
      }),
      "inspect",
    );
    const observations = (inspected.record as Record<string, unknown>)
      .observations as readonly Record<string, unknown>[];
    const fresh = observations.at(-1);
    assert(
      fresh && String(fresh.validUntil) > new Date().toISOString(),
      "inspect lacks a fresh launcher observation",
    );

    assert(
      await rootExists(join(stateRoot, environmentId, "environment.json")),
      "create did not persist the environment state metadata",
    );
    const getState = successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "get_state",
        environmentId,
        generation,
        requestId: "real-host-get-state-1",
      }),
      "get_state",
    );
    const stateJson = JSON.parse(
      String((getState.outcome as Record<string, unknown>).stdout),
    ) as Record<string, unknown>;
    const isolation = stateJson.isolation as Record<string, unknown>;
    assert(
      stateJson.omp !== undefined &&
        Array.isArray(isolation.deniedHostPaths) &&
        isolation.deniedHostPaths.length === 4,
      "guest did not report host-path isolation measurements",
    );
    assert(
      (isolation.guestStore as Record<string, unknown>).source === "/dev/vda" &&
        (isolation.guestStore as Record<string, unknown>).fsType === "erofs",
      "guest store is not the guest read-only device",
    );
    assert(
      JSON.stringify(isolation.interfaces) === '["lo"]' &&
        (isolation.nameservers as unknown[]).length === 0,
      "guest network or DNS isolation failed",
    );

    successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "drain",
        environmentId,
      }),
      "drain",
    );
    const rejected = await runController(adlcRoot, controller, databasePath, directory, {
      command: "get_state",
      environmentId,
      generation,
      requestId: "real-host-drained-request",
    });
    assert(
      rejected.exitCode !== 0 && rejected.response.command === "failure",
      "drained environment accepted a guest RPC",
    );
    const directlyRejected = await runLauncher(runtime, {
      action: "rpc",
      frame: {
        _tag: "SelfHostedGuestRpcRequest",
        environmentId,
        generation,
        requestId: "real-host-direct-drained-request",
        operation: "get_state",
        payload: {},
      },
    });
    assert(
      directlyRejected.exitCode !== 0 && directlyRejected.stderr.includes("generation is draining"),
      "direct launcher RPC bypassed persisted drain state",
    );
    const stopped = successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "stop",
        environmentId,
      }),
      "stop",
    );
    const stoppedRecord = stopped.record as Record<string, unknown>;
    assert(
      (stoppedRecord.capacityLease as Record<string, unknown>).releasedAt === undefined,
      "stop released the scheduler lease",
    );
    assert(
      !(await rootExists(`/proc/${String(first.state.pid)}`)),
      "stop left the VMM process live",
    );
    assert(
      await rootExists(join(stateRoot, environmentId, "state.img")),
      "stop removed the environment state image",
    );
    assert(
      await rootExists(join(stateRoot, environmentId, "environment.json")),
      "stop removed the environment state metadata",
    );

    const recovered = successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "recover",
        environmentId,
      }),
      "recover",
    );
    const recoveredRecord = recovered.record as Record<string, unknown>;
    const recoveredGeneration = recoveredRecord.activeGeneration as Record<string, unknown>;
    const recoveredReceipt = (
      recoveredRecord.materializationReceipts as readonly Record<string, unknown>[]
    ).at(-1);
    const persistedEnvironment = await rootText(join(stateRoot, environmentId, "environment.json"));
    assert(
      recoveredRecord.lifecycle === "Ready" &&
        recoveredGeneration.ordinal === 2 &&
        recoveredReceipt?.initialStateVolumeDigest === receipt.initialStateVolumeDigest,
      `recover did not preserve the environment state volume into generation 2: lifecycle=${String(recoveredRecord.lifecycle)} ordinal=${String(recoveredGeneration.ordinal)} initial=${String(receipt.initialStateVolumeDigest)} recovered=${String(recoveredReceipt?.initialStateVolumeDigest)} environment=${persistedEnvironment.trim()}`,
    );
    const second = await recordState(stateRoot, environmentId, recoveredGeneration);

    const destroyed = successful(
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "destroy",
        environmentId,
      }),
      "destroy",
    );
    created = false;
    for (const path of [
      `/proc/${String(second.state.pid)}`,
      `/proc/${String(second.state.netnsPid)}`,
      second.base,
      join(stateRoot, environmentId, "state.img"),
    ])
      await rootAbsent(path);
    const destroyedRecord = destroyed.record as Record<string, unknown>;
    assert(
      destroyedRecord.lifecycle === "Destroyed" &&
        typeof (destroyedRecord.capacityLease as Record<string, unknown>).releasedAt === "string",
      "destroy did not release the lease after cleanup",
    );
    console.log(
      JSON.stringify({
        status: "passed",
        mode,
        environmentId,
        initialGeneration: generation,
        recoveredGeneration,
        receipt: {
          cgroupPath: receipt.cgroupPath,
          cgroupControls: receipt.cgroupControls,
          vsockCid: receipt.vsockCid,
          vsockPort: receipt.vsockPort,
        },
        guestState: stateJson,
      }),
    );
  }
} finally {
  try {
    if (created && runtime)
      await runController(adlcRoot, controller, databasePath, directory, {
        command: "destroy",
        environmentId,
      });
  } finally {
    if (runtime) await runtime.cleanup();
    const failureLogRoot = join(directory, "failure-logs");
    if (!created && existsSync(failureLogRoot)) {
      for (const log of readdirSync(failureLogRoot))
        console.error(readFileSync(join(failureLogRoot, log), "utf8"));
    }
    await sudo(["rm", "-rf", directory], "remove transient test directory");
    rmSync(seedPath, { force: true });
  }
}
