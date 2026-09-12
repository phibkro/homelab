import { afterEach, expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { once } from "node:events";
import { createConnection } from "node:net";
import { join } from "node:path";
import { startIpcServer } from "../src/daemon.ts";
import { acquireDaemonLock } from "../src/daemon-lock.ts";
import { DesktopSettingsError } from "../src/contracts.ts";
import { JobStore, ProfileStore, writeAtomic } from "../src/files.ts";
import { encodeFrame, readFrame } from "../src/framing.ts";
import { verifyGenerationMetadata } from "../src/runtime.ts";
import { DesktopSettingsService, type ServiceConfig } from "../src/service.ts";

const temporaryDirectories: string[] = [];

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "nori-desktop-settings-"));
  temporaryDirectories.push(root);
  const dataDirectory = join(root, "data");
  await mkdir(dataDirectory, { recursive: true, mode: 0o700 });
  await Bun.write(
    join(dataDirectory, "settings-input.schema.json"),
    JSON.stringify({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      $defs: {
        NoriDesktopSettingsInput: {
          type: "object",
          properties: {
            "desktop.waybar": {
              type: "object",
              properties: { position: { enum: ["top", "bottom"] } },
              required: ["position"],
              additionalProperties: false,
            },
          },
          required: ["desktop.waybar"],
          additionalProperties: false,
        },
      },
    }),
  );
  await Bun.write(
    join(dataDirectory, "settings-output.schema.json"),
    JSON.stringify({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      $defs: { NoriDesktopSettingsOutput: { type: "object" } },
    }),
  );
  await Bun.write(
    join(dataDirectory, "components.json"),
    JSON.stringify({
      "desktop.waybar": {
        settings: { position: { title: "Bar position", control: "enum", applyClass: "generation" } },
      },
    }),
  );
  await Bun.write(
    join(dataDirectory, "resolved-settings.json"),
    JSON.stringify({ "desktop.waybar": { position: "top", enabled: true } }),
  );
  const evaluator = join(root, "evaluator");
  const builder = join(root, "builder");
  const renderer = `#!/bin/sh
revision=$(sed -n 's/.*"revision": \\([0-9][0-9]*\\).*/\\1/p' "$2")
printf '{"metadata":{"source":"/nix/store/approved-source","profileRevision":%s,"profileHash":"%s"},"resolved":{"desktop.waybar":{"position":"bottom","enabled":true}}' "$revision" "$4"`;
  await Bun.write(evaluator, `${renderer}\nprintf '}\\n'\n`);
  await Bun.write(builder, `${renderer}\nprintf ',"artifact":"/nix/store/generated"}\\n'\n`);
  await chmod(evaluator, 0o755);
  await chmod(builder, 0o755);
  await Bun.write(
    join(root, "approved-source.json"),
    `${JSON.stringify({ source: "/nix/store/approved-source", host: "workstation" })}\n`,
  );
  const config: ServiceConfig = {
    configHome: join(root, "config"),
    stateHome: join(root, "state"),
    dataDirectory,
    approvedSource: join(root, "approved-source.json"),
    riceCommand: "rice-saved-command",
    shell: "/bin/sh",
    builder,
    evaluator,
    activator: "/does-not-run",
    activeMetadata: join(root, "generation.json"),
    systemctl: "/does-not-run",
    hyprctl: "/does-not-run",
    pkexec: "/does-not-run",
  };
  return { config, root };
}

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) => rm(directory, { force: true, recursive: true })),
  );
});


test("daemon singleton lock rejects a concurrent start before service construction", async () => {
  const { config } = await fixture();
  const release = await acquireDaemonLock(config.stateHome);
  try {
    await expect(acquireDaemonLock(config.stateHome)).rejects.toMatchObject({
      code: "unavailable",
      message: "nori-desktop-config is already running",
    });
  } finally {
    await release();
  }
  await (await acquireDaemonLock(config.stateHome))();
});
function quoteShell(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

async function invoke(
  runner: string,
  env: Record<string, string | undefined>,
  args: ReadonlyArray<string>,
  input?: string,
) {
  const child = Bun.spawn([runner, ...args], {
    env,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  if (input !== undefined) child.stdin.write(input);
  child.stdin.end();
  const [status, stdout, stderr] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  return { status, stdout, stderr };
}

test("revision compare-and-swap preserves the first committed profile", async () => {
  const { config } = await fixture();
  const service = await DesktopSettingsService.make(config);
  const preview = await service.preview({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
  });
  const first = await service.change({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
    previewId: preview.id,
  });
  expect(first.profile.revision).toBe(1);
  expect(first.profile.components).toEqual({ "desktop.waybar": { position: "bottom" } });
  await expect(
    service.change({
      component: "desktop.waybar",
      setting: "position",
      value: "top",
      expectedRevision: 0,
      previewId: preview.id,
    }),
  ).rejects.toMatchObject({ code: "revision_conflict" });
  expect((await service.state()).profile).toEqual(first.profile);
});

test("restart recovers a persisted profile whose preview receipt was not marked committed", async () => {
  const { config } = await fixture();
  const service = await DesktopSettingsService.make(config);
  const preview = await service.preview({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
  });
  await service.change({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
    previewId: preview.id,
  });

  const path = join(config.stateHome, "previews", `${preview.id}.json`);
  const receipt = JSON.parse(await readFile(path, "utf8"));
  delete receipt.committedAt;
  await Bun.write(path, `${JSON.stringify(receipt)}\n`);

  expect((await DesktopSettingsService.make(config)).state()).resolves.toMatchObject({
    committedPreviewId: preview.id,
    profile: { revision: 1 },
  });
});

test("preview evaluates a candidate without persisting the draft", async () => {
  const { config } = await fixture();
  const service = await DesktopSettingsService.make(config);

  const preview = await service.preview({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
  });

  expect(preview.profile.revision).toBe(1);
  expect(preview.profile.components).toEqual({ "desktop.waybar": { position: "bottom" } });
  expect(preview.resolved).toEqual({ "desktop.waybar": { position: "bottom", enabled: true } });
  expect(preview.impact).toEqual({ applyClass: "generation", requiresGeneration: true });
  expect((await service.state()).profile).toEqual({
    formatVersion: 1,
    revision: 0,
    components: { "desktop.waybar": { position: "top" } },
    savedCommands: [],
  });
});

test("generated schema rejects a non-writable enum value before profile persistence", async () => {
  const { config } = await fixture();
  const service = await DesktopSettingsService.make(config);
  await expect(
    service.preview({
      component: "desktop.waybar",
      setting: "position",
      value: "left",
      expectedRevision: 0,
    }),
  ).rejects.toMatchObject({ code: "invalid_profile" });
  expect((await service.state()).profile.revision).toBe(0);
  expect((await service.state()).profile.components).toEqual({
    "desktop.waybar": { position: "top" },
  });
});

test("an interrupted atomic replacement leaves the last complete profile readable", async () => {
  const { root } = await fixture();
  const store = new ProfileStore(join(root, "config", "nori-desktop"), join(root, "state", "nori-desktop"));
  const initial = await store.initialize({ "desktop.waybar": { position: "top" } });
  await Bun.write(`${store.paths.profile}.simulated-crash.tmp`, '{"revision":');
  expect((await store.read()).hash).toBe(initial.hash);
  expect(await readFile(store.paths.profile, "utf8")).toBe(initial.bytes);
  await writeAtomic(store.paths.profile, initial.bytes);
  expect((await store.read()).profile.revision).toBe(0);
});

test("service restart marks an unfinished apply as interrupted", async () => {
  const { config } = await fixture();
  const jobs = new JobStore(config.stateHome);
  await jobs.initialize();
  await jobs.save({
    id: "unfinished",
    revision: 1,
    profileHash: "candidate",
    status: "activating",
    createdAt: "2026-09-12T00:00:00.000Z",
    updatedAt: "2026-09-12T00:00:01.000Z",
    log: ["Activation started"],
  });

  const restarted = await DesktopSettingsService.make(config);
  const [recovered] = (await restarted.state()).jobs;
  expect(recovered?.status).toBe("interrupted");
  expect(recovered?.error).toMatchObject({ code: "interrupted" });
  expect(recovered?.log).toContain("Daemon restart marked unfinished apply as interrupted");
});

test("authorization cancellation durably fails exactly one awaiting apply", async () => {
  const { config } = await fixture();
  const jobs = new JobStore(config.stateHome);
  await jobs.initialize();
  await jobs.save({
    id: "awaiting-auth",
    revision: 1,
    profileHash: "a".repeat(64),
    status: "awaiting_authorization",
    createdAt: "2026-09-12T00:00:00.000Z",
    updatedAt: "2026-09-12T00:00:01.000Z",
    log: ["Awaiting authorization"],
  });
  const service = await DesktopSettingsService.make(config);
  const failed = await service.authorizationFailed({ applyId: "awaiting-auth" });
  expect(failed).toMatchObject({
    status: "failed",
    error: { code: "activation_rejected", message: "Authorization was cancelled or denied" },
  });
  await expect(service.authorizationFailed({ applyId: "awaiting-auth" })).rejects.toMatchObject({
    code: "not_found",
  });
});

test("reconciliation activates only when the authority reads the matching generation identity", async () => {
  const { config } = await fixture();
  const jobs = new JobStore(config.stateHome);
  await jobs.initialize();
  const job = {
    id: "reconcile",
    revision: 1,
    profileHash: "b".repeat(64),
    source: "/nix/store/approved-source",
    previewArtifact: "/nix/store/generated",
    status: "reconciling" as const,
    createdAt: "2026-09-12T00:00:00.000Z",
    updatedAt: "2026-09-12T00:00:01.000Z",
    log: ["Generation activated"],
  };
  await jobs.save(job);
  const service = await DesktopSettingsService.make(config);
  await jobs.save(job);
  service.desktop.activeGeneration = async () => ({
    path: "/nix/store/current-system",
    source: job.source,
    profileRevision: job.revision,
    profileHash: job.profileHash,
  });
  const active = await service.reconcile({
    applyId: job.id,
    observed: { waybar: { unit: "active", edge: "bottom" } },
  });
  expect(active.status).toBe("active");
  await jobs.save({ ...job, id: "stale", status: "reconciling" });
  service.desktop.activeGeneration = async () => ({
    path: "/nix/store/current-system",
    source: job.source,
    profileRevision: 2,
    profileHash: job.profileHash,
  });
  const failed = await service.reconcile({
    applyId: "stale",
    observed: { waybar: { unit: "active", edge: "bottom" } },
  });
  expect(failed).toMatchObject({ status: "failed", error: { code: "activation_rejected" } });
});

test("reconciliation records a failed user runtime observation after a matching activation", async () => {
  const { config } = await fixture();
  const jobs = new JobStore(config.stateHome);
  await jobs.initialize();
  const job = {
    id: "runtime-failed",
    revision: 1,
    profileHash: "c".repeat(64),
    source: "/nix/store/approved-source",
    previewArtifact: "/nix/store/generated",
    status: "reconciling" as const,
    createdAt: "2026-09-12T00:00:00.000Z",
    updatedAt: "2026-09-12T00:00:01.000Z",
    log: ["Generation activated"],
  };
  await jobs.save(job);
  await jobs.save(job);
  const service = await DesktopSettingsService.make(config);
  await jobs.save(job);
  service.desktop.activeGeneration = async () => ({
    path: "/nix/store/current-system",
    source: job.source,
    profileRevision: job.revision,
    profileHash: job.profileHash,
  });
  const failed = await service.reconcile({
    applyId: job.id,
    observed: { waybar: { unit: "failed", edge: "unavailable", reason: "unit exited" } },
  });
  expect(failed).toMatchObject({ status: "failed", error: { code: "runtime_unavailable" } });
});

test("saved command IPC round trip keeps a parameter literal across the generated script", async () => {
  const { config, root } = await fixture();
  const runner = join(root, "rice-saved-command");
  const service = await DesktopSettingsService.make({ ...config, riceCommand: runner });
  const socket = join(root, "runtime", "settings.sock");
  const server = await startIpcServer(service, socket);
  try {
    const shell = Bun.which("sh");
    if (shell === null) throw new Error("The test requires sh");
    const main = join(import.meta.dir, "..", "src", "rice-saved-command.ts");
    await Bun.write(
      runner,
      `#!${shell}\nexec ${quoteShell(process.execPath)} ${quoteShell(main)} "$@"\n`,
    );
    await chmod(runner, 0o755);
    const env = {
      ...process.env,
      HOME: root,
      XDG_CONFIG_HOME: join(root, "config"),
      XDG_DATA_HOME: join(root, "projected"),
      NORI_DESKTOP_SETTINGS_RICE_COMMAND: runner,
      NORI_DESKTOP_SETTINGS_SHELL: shell,
      NORI_DESKTOP_SETTINGS_SOCKET: socket,
      RICE_VICINAE_BIN: undefined,
    };
    const marker = join(root, "should-not-exist");
    const literal = `hello; touch ${marker}`;
    const request = {
      title: "Literal parameter",
      outputMode: "fullOutput",
      parameters: [{ name: "message", optional: false }],
      execution: {
        type: "argv",
        executable: shell,
        arguments: ["-c", 'printf "%s\\n" "$1"', "rice-test", "{{message}}"],
      },
    };

    const created = await invoke(runner, env, ["create"], JSON.stringify(request));
    expect(created.status).toBe(0);
    const scriptDirectory = join(root, "projected", "vicinae", "scripts", "nori-saved");
    const [scriptName] = await readdir(scriptDirectory);
    expect(scriptName).toBeDefined();
    const ran = await invoke(join(scriptDirectory, scriptName!), env, [literal]);
    if (ran.status !== 0) throw new Error(`Generated command failed (${ran.status}): ${ran.stderr}`);
    expect(ran.stdout).toBe(`${literal}\n`);
    expect(await Bun.file(marker).exists()).toBe(false);

    const failing = await invoke(
      runner,
      env,
      ["create"],
      JSON.stringify({
        title: "Expected failure",
        outputMode: "fullOutput",
        parameters: [],
        execution: { type: "argv", executable: shell, arguments: ["-c", "printf failure >&2; exit 23"] },
      }),
    );
    expect(failing.status).toBe(0);
    const scripts = await readdir(scriptDirectory);
    const failingScript = scripts.find((name) => name !== scriptName);
    expect(failingScript).toBeDefined();
    const failedRun = await invoke(join(scriptDirectory, failingScript!), env, []);
    expect(failedRun).toMatchObject({ status: 23 });
    expect(failedRun.stderr).toContain("failure");

    for (const executable of ["doas", "pkexec", "run0", "su", "sudo", "sudoedit"]) {
      const rejected = await invoke(
        runner,
        env,
        ["create"],
        JSON.stringify({
          title: "Forbidden",
          outputMode: "fullOutput",
          parameters: [],
          execution: { type: "argv", executable, arguments: ["true"] },
        }),
      );
      expect(rejected).toMatchObject({ status: 64 });
    }

    const shellCommand = await invoke(
      runner,
      env,
      ["create"],
      JSON.stringify({
        title: "Explicit shell",
        outputMode: "fullOutput",
        parameters: [{ name: "message", optional: false }],
        execution: { type: "shell", source: 'printf "%s\\n" "$1"' },
      }),
    );
    expect(shellCommand.status).toBe(0);
    const shellScript = (await readdir(scriptDirectory)).find((name) => name.includes("explicit-shell"));
    expect(shellScript).toBeDefined();
    expect(await invoke(join(scriptDirectory, shellScript!), env, ["shell parameter"])).toMatchObject({
      status: 0,
      stdout: "shell parameter\n",
    });

    const implicitShell = await invoke(
      runner,
      env,
      ["create"],
      JSON.stringify({
        title: "Implicit shell",
        outputMode: "fullOutput",
        parameters: [],
        execution: { type: "argv", executable: 'printf "%s"', arguments: [] },
      }),
    );
    expect(implicitShell).toMatchObject({ status: 64 });
  } finally {
    server.stop(true);
  }
});
test("daemon rejects a second framed request before dispatching either request", async () => {
  const { config, root } = await fixture();
  const service = await DesktopSettingsService.make(config);
  const socketPath = join(root, "runtime", "settings.sock");
  const server = await startIpcServer(service, socketPath);
  const client = createConnection({ path: socketPath, allowHalfOpen: true });
  try {
    await once(client, "connect");
    client.write(Buffer.concat([encodeFrame({ operation: "state" }), encodeFrame({ operation: "state" })]));
    const response = JSON.parse(await readFrame(client)) as { ok: boolean; error?: { code?: string } };
    expect(response).toMatchObject({ ok: false, error: { code: "invalid_request" } });
    expect((await service.state()).profile.revision).toBe(0);
  } finally {
    client.destroy();
    server.stop(true);
  }
});

test("apply returns a durable queued job before the managed build finishes", async () => {
  const { config, root } = await fixture();
  const shell = Bun.which("sh");
  const mkfifo = Bun.which("mkfifo");
  if (shell === null || mkfifo === null) throw new Error("The test requires sh and mkfifo");
  const previewService = await DesktopSettingsService.make(config);
  const preview = await previewService.preview({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
  });
  await previewService.change({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
    previewId: preview.id,
  });
  const gate = join(root, "builder-gate");
  const makeGate = Bun.spawn([mkfifo, gate]);
  expect(await makeGate.exited).toBe(0);
  const builder = join(root, "blocked-builder");
  await Bun.write(builder, `#!${shell}\nread -r _ < ${quoteShell(gate)}\nexit 23\n`);
  await chmod(builder, 0o755);
  const service = await DesktopSettingsService.make({ ...config, builder });
  const scheduled = await service.apply({ expectedRevision: 1, previewId: preview.id });
  expect(scheduled.status).toBe("queued");
  const completion = service.running.get(scheduled.id);
  if (completion === undefined) throw new Error("The apply job was not started");

  const release = Bun.spawn([shell, "-c", `printf '%s\\n' go > ${quoteShell(gate)}`]);
  expect(await release.exited).toBe(0);
  await completion;

  const job = (await service.state()).jobs.find((candidate) => candidate.id === scheduled.id);
  expect(job?.status).toBe("failed");
  expect(job?.error?.message).toBe("Immutable workstation build failed");
});


test("activation metadata cannot substitute a different source, revision, or profile hash", () => {
  expect(() =>
    verifyGenerationMetadata(
      { source: "/nix/store/other-source", profileRevision: 2, profileHash: "other" },
      "/nix/store/approved-source",
      1,
      "expected",
    ),
  ).toThrow(DesktopSettingsError);
});
