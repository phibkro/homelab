/* runtime-adapter: legacy rice-saved-command behavior backed only by the shared daemon profile. */
import { createHash } from "node:crypto";
import { chmod, mkdir, readdir, readlink, rename, rm, symlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Effect, Schema } from "effect";
import { callService } from "./cli.ts";
import { DesktopSettingsError, Profile, parseJson, decodeProfile } from "./contracts.ts";
import {
  commandArguments,
  decodeSavedCommand,
  type SavedCommand,
} from "./saved-command.ts";

const Projection = Schema.Struct({
  id: Schema.String,
  filename: Schema.String,
  script: Schema.String,
});

type Projection = typeof Projection.Type;

type Runtime = {
  readonly dataHome: string;
  readonly runner: string;
  readonly shell: string;
  readonly vicinae: string | undefined;
};

function runtimeFromEnvironment(): Runtime {
  const home = process.env.HOME;
  if (home === undefined || home.length === 0) {
    throw new DesktopSettingsError("unavailable", "HOME is not configured");
  }
  const dataHome = process.env.XDG_DATA_HOME ?? join(home, ".local", "share");
  return {
    dataHome,
    runner: process.env.NORI_DESKTOP_SETTINGS_RICE_COMMAND ?? Bun.argv[1] ?? "rice-saved-command",
    shell: process.env.NORI_DESKTOP_SETTINGS_SHELL ?? "/bin/sh",
    vicinae: process.env.RICE_VICINAE_BIN,
  };
}

function value(response: Record<string, unknown>, key: string): unknown {
  const result = response[key];
  if (result === undefined) {
    throw new DesktopSettingsError("unavailable", `Settings service response omitted ${key}`);
  }
  return result;
}

async function profileFrom(response: Record<string, unknown>) {
  return Effect.runPromise(
    Schema.decodeUnknownEffect(Profile)(value(response, "profile")).pipe(Effect.flatMap(decodeProfile)),
  );
}

async function commandFrom(response: Record<string, unknown>): Promise<SavedCommand> {
  return Effect.runPromise(decodeSavedCommand(value(response, "command")));
}

async function projectionsFrom(response: Record<string, unknown>): Promise<ReadonlyArray<Projection>> {
  return Effect.runPromise(
    Schema.decodeUnknownEffect(Schema.Array(Projection))(value(response, "scripts")),
  );
}

function projectionName(revision: number, runtime: Runtime): string {
  const runtimeHash = createHash("sha256")
    .update(runtime.runner)
    .update("\0")
    .update(runtime.shell)
    .digest("hex")
    .slice(0, 12);
  return `${revision}-${runtimeHash}`;
}

async function renderProjection(
  profileRevision: number,
  scripts: ReadonlyArray<Projection>,
  runtime: Runtime,
): Promise<string> {
  const revisions = join(runtime.dataHome, "vicinae", "scripts", ".nori-saved-revisions");
  await mkdir(revisions, { recursive: true, mode: 0o700 });
  const target = join(revisions, projectionName(profileRevision, runtime));
  if (await Bun.file(target).exists()) return target;
  const temporary = join(revisions, `.${projectionName(profileRevision, runtime)}.${process.pid}.${crypto.randomUUID()}.tmp`);
  await mkdir(temporary, { mode: 0o700 });
  try {
    for (const script of scripts) {
      const path = join(temporary, script.filename);
      await Bun.write(path, script.script);
      await chmod(path, 0o755);
    }
    await rename(temporary, target);
  } finally {
    await rm(temporary, { force: true, recursive: true });
  }
  return target;
}

async function pointAtProjection(target: string, runtime: Runtime): Promise<void> {
  const link = join(runtime.dataHome, "vicinae", "scripts", "nori-saved");
  await mkdir(dirname(link), { recursive: true, mode: 0o700 });
  const temporary = `${link}.${process.pid}.${crypto.randomUUID()}.tmp`;
  try {
    await symlink(target, temporary, "dir");
    await rename(temporary, link);
  } finally {
    await rm(temporary, { force: true });
  }
}

async function refreshVicinae(binary: string | undefined): Promise<boolean> {
  if (binary === undefined || binary.length === 0) return false;
  try {
    const child = Bun.spawn([binary, "deeplink", "vicinae://launch/core/reload-scripts"], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    });
    return (await child.exited) === 0;
  } catch {
    return false;
  }
}

async function cleanOldProjections(keep: ReadonlyArray<string>, runtime: Runtime): Promise<void> {
  const revisions = join(runtime.dataHome, "vicinae", "scripts", ".nori-saved-revisions");
  const keepNames = new Set(keep.map((path) => path.split("/").at(-1)));
  try {
    for (const name of await readdir(revisions)) {
      if (!keepNames.has(name)) await rm(join(revisions, name), { force: true, recursive: true });
    }
  } catch {
    // Projection cleanup is best-effort and never changes the profile authority.
  }
}

async function synchronize(runtime: Runtime): Promise<boolean> {
  const response = await callService("/v1/saved-commands/projection", "GET");
  const [profile, scripts] = await Promise.all([profileFrom(response), projectionsFrom(response)]);
  const target = await renderProjection(profile.revision, scripts, runtime);
  const link = join(runtime.dataHome, "vicinae", "scripts", "nori-saved");
  let previous: string | undefined;
  try {
    previous = await readlink(link);
  } catch (cause) {
    if (!(cause instanceof Error && "code" in cause && cause.code === "ENOENT")) throw cause;
  }
  if (previous !== target) await pointAtProjection(target, runtime);
  const refreshed = await refreshVicinae(runtime.vicinae);
  await cleanOldProjections([target, ...(previous === undefined ? [] : [previous])], runtime);
  return refreshed;
}

async function create(runtime: Runtime): Promise<void> {
  const input = await Bun.stdin.text();
  const request = await Effect.runPromise(parseJson(Schema.Unknown, input, "saved-command create request"));
  const profile = await profileFrom(await callService("/v1/saved-commands", "GET"));
  const response = await callService("/v1/saved-commands/create", "POST", {
    request,
    expectedRevision: profile.revision,
  });
  const command = await commandFrom(response);
  const refreshed = await synchronize(runtime);
  process.stdout.write(`${JSON.stringify({ command, refreshed })}\n`);
}

async function list(): Promise<void> {
  const profile = await profileFrom(await callService("/v1/saved-commands", "GET"));
  process.stdout.write(
    `${JSON.stringify({ version: 1, revision: profile.revision, commands: profile.savedCommands })}\n`,
  );
}

async function run(id: string, values: ReadonlyArray<string>, runtime: Runtime): Promise<number> {
  const command = await commandFrom(
    await callService("/v1/saved-commands/lookup", "POST", { id }),
  );
  const arguments_ = await Effect.runPromise(commandArguments(command, values));
  const invocation =
    command.execution.type === "argv"
      ? [command.execution.executable, ...arguments_]
      : [runtime.shell, "-c", command.execution.source, "rice-saved-command", ...arguments_];
  const child = Bun.spawn(invocation, {
    ...(command.workingDirectory === undefined ? {} : { cwd: command.workingDirectory }),
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  return child.exited;
}

async function program(args: ReadonlyArray<string>): Promise<number> {
  const runtime = runtimeFromEnvironment();
  const [operation, ...rest] = args;
  if (operation === "create" && rest.length === 0) {
    await create(runtime);
    return 0;
  }
  if (operation === "list" && rest.length === 0) {
    await list();
    return 0;
  }
  if (operation === "sync" && rest.length === 0) {
    await synchronize(runtime);
    return 0;
  }
  if (operation === "run") {
    const separator = rest.indexOf("--");
    const id = rest[0];
    if (id === undefined || separator !== 1) {
      throw new DesktopSettingsError(
        "invalid_request",
        "usage: rice-saved-command run COMMAND_ID -- [PARAMETER ...]",
      );
    }
    return run(id, rest.slice(separator + 1), runtime);
  }
  throw new DesktopSettingsError("invalid_request", "usage: rice-saved-command {create|list|sync|run}");
}

try {
  process.exitCode = await program(Bun.argv.slice(2));
} catch (cause) {
  process.stderr.write(
    `rice-saved-command: ${cause instanceof Error ? cause.message : String(cause)}\n`,
  );
  process.exitCode = 64;
}
