import { createHash } from "node:crypto";
import { chmod, mkdir, readdir, readlink, rename, rm, symlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Effect, Schema } from "effect";
import {
  CommandError,
  SavedCommandProfile,
  commandArguments,
  decodeCreateRequest,
  decodeProfile,
  makeSavedCommand,
  renderScript,
  type SavedCommand,
  type SavedCommandProfile as SavedCommandProfileType,
} from "./model.ts";

const emptyProfile: SavedCommandProfileType = {
  version: 1,
  revision: 0,
  commands: [],
};

const strictParseOptions = {
  errors: "all",
  onExcessProperty: "error",
} as const;

const ProfileJson = Schema.fromJsonString(SavedCommandProfile, { space: 2 });

type AppPaths = {
  readonly profile: string;
  readonly scriptLink: string;
  readonly revisions: string;
};

type Runtime = {
  readonly paths: AppPaths;
  readonly runner: string;
  readonly shell: string;
  readonly vicinae: string | undefined;
};

function describeCause(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}

function tryPromise<A>(label: string, run: () => Promise<A>) {
  return Effect.tryPromise({
    try: run,
    catch: (cause) => new CommandError({ message: `${label}: ${describeCause(cause)}` }),
  });
}

function runtimeFromEnvironment(): Effect.Effect<Runtime, CommandError> {
  const home = process.env.HOME;
  const runner = process.env.RICE_SAVED_COMMAND_BIN;
  const shell = process.env.RICE_SAVED_COMMAND_SHELL;
  if (home === undefined || home.length === 0) {
    return Effect.fail(new CommandError({ message: "HOME is not configured" }));
  }
  if (runner === undefined || runner.length === 0) {
    return Effect.fail(new CommandError({ message: "RICE_SAVED_COMMAND_BIN is not configured" }));
  }
  if (shell === undefined || shell.length === 0) {
    return Effect.fail(new CommandError({ message: "RICE_SAVED_COMMAND_SHELL is not configured" }));
  }

  const configHome = process.env.XDG_CONFIG_HOME ?? join(home, ".config");
  const dataHome = process.env.XDG_DATA_HOME ?? join(home, ".local", "share");
  return Effect.succeed({
    paths: {
      profile: join(configHome, "nori-desktop", "saved-commands.json"),
      scriptLink: join(dataHome, "vicinae", "scripts", "nori-saved"),
      revisions: join(dataHome, "vicinae", "scripts", ".nori-saved-revisions"),
    },
    runner,
    shell,
    vicinae: process.env.RICE_VICINAE_BIN,
  });
}

function loadProfile(path: string) {
  return tryPromise("Cannot read saved-command profile", async () => {
    const file = Bun.file(path);
    return (await file.exists()) ? await file.text() : undefined;
  }).pipe(
    Effect.flatMap((text) => {
      if (text === undefined) return Effect.succeed(emptyProfile);
      return Schema.decodeUnknownEffect(
        ProfileJson,
        strictParseOptions,
      )(text).pipe(
        Effect.mapError(
          (error) =>
            new CommandError({
              message: `Invalid saved-command profile: ${error}`,
            }),
        ),
        Effect.flatMap(decodeProfile),
      );
    }),
  );
}

function encodeProfile(profile: SavedCommandProfileType) {
  return Schema.encodeEffect(ProfileJson)(profile).pipe(
    Effect.mapError(
      (error) => new CommandError({ message: `Cannot encode saved-command profile: ${error}` }),
    ),
  );
}

function writeAtomic(path: string, content: string, mode: number) {
  return tryPromise(`Cannot replace ${path}`, async () => {
    await mkdir(dirname(path), { recursive: true, mode: 0o700 });
    const temporary = `${path}.${process.pid}.${crypto.randomUUID()}.tmp`;
    try {
      await Bun.write(temporary, content);
      await chmod(temporary, mode);
      await rename(temporary, path);
    } finally {
      await rm(temporary, { force: true });
    }
  });
}

function projectionName(profile: SavedCommandProfileType, runtime: Runtime): string {
  const runtimeHash = createHash("sha256")
    .update(runtime.runner)
    .update("\0")
    .update(runtime.shell)
    .digest("hex")
    .slice(0, 12);
  return `${profile.revision}-${runtimeHash}`;
}

function renderProjection(profile: SavedCommandProfileType, runtime: Runtime) {
  return tryPromise("Cannot render saved-command scripts", async () => {
    await mkdir(runtime.paths.revisions, { recursive: true, mode: 0o700 });
    const name = projectionName(profile, runtime);
    const target = join(runtime.paths.revisions, name);
    if (await Bun.file(target).exists()) return target;

    const temporary = join(
      runtime.paths.revisions,
      `.${name}.${process.pid}.${crypto.randomUUID()}.tmp`,
    );
    await mkdir(temporary, { mode: 0o700 });
    try {
      for (const command of profile.commands) {
        const filename = `${command.id.replaceAll(".", "-")}.sh`;
        const path = join(temporary, filename);
        await Bun.write(path, renderScript(command, runtime.runner, runtime.shell));
        await chmod(path, 0o755);
      }
      await rename(temporary, target);
    } finally {
      await rm(temporary, { force: true, recursive: true });
    }
    return target;
  });
}

function pointAtProjection(target: string, link: string) {
  return tryPromise("Cannot activate saved-command scripts", async () => {
    await mkdir(dirname(link), { recursive: true });
    const temporary = `${link}.${process.pid}.${crypto.randomUUID()}.tmp`;
    try {
      await symlink(target, temporary, "dir");
      await rename(temporary, link);
    } finally {
      await rm(temporary, { force: true });
    }
  });
}

function synchronizeProjection(profile: SavedCommandProfileType, runtime: Runtime) {
  return Effect.gen(function* () {
    const target = yield* renderProjection(profile, runtime);
    const current = yield* tryPromise(
      "Cannot inspect saved-command script projection",
      async () => {
        try {
          return await readlink(runtime.paths.scriptLink);
        } catch (cause) {
          if (cause instanceof Error && "code" in cause && cause.code === "ENOENT") {
            return undefined;
          }
          throw cause;
        }
      },
    );
    if (current !== target) {
      yield* pointAtProjection(target, runtime.paths.scriptLink);
    }
    return target;
  });
}

function refreshVicinae(binary: string | undefined) {
  if (binary === undefined) return Effect.succeed(false);
  return Effect.tryPromise(async () => {
    const process = Bun.spawn([binary, "deeplink", "vicinae://launch/core/reload-scripts"], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    });
    return (await process.exited) === 0;
  }).pipe(Effect.catch(() => Effect.succeed(false)));
}

function cleanOldProjections(keep: ReadonlyArray<string>, runtime: Runtime) {
  return tryPromise("Cannot clean old saved-command scripts", async () => {
    const keepNames = new Set(keep.map((path) => path.split("/").at(-1)));
    for (const name of await readdir(runtime.paths.revisions)) {
      if (!keepNames.has(name)) {
        await rm(join(runtime.paths.revisions, name), {
          force: true,
          recursive: true,
        });
      }
    }
  }).pipe(Effect.catch(() => Effect.void));
}

function createCommand(runtime: Runtime) {
  return Effect.gen(function* () {
    const input = yield* tryPromise("Cannot read create request", () => Bun.stdin.text());
    const request = yield* Schema.decodeUnknownEffect(Schema.fromJsonString(Schema.Unknown))(
      input,
    ).pipe(
      Effect.mapError((error) => new CommandError({ message: `Invalid JSON request: ${error}` })),
      Effect.flatMap(decodeCreateRequest),
    );
    const previous = yield* loadProfile(runtime.paths.profile);
    const previousProjection = yield* synchronizeProjection(previous, runtime);
    const command = makeSavedCommand(request);
    const next: SavedCommandProfileType = {
      version: 1,
      revision: previous.revision + 1,
      commands: [...previous.commands, command],
    };
    const nextProjection = yield* renderProjection(next, runtime);
    yield* pointAtProjection(nextProjection, runtime.paths.scriptLink);
    const encoded = yield* encodeProfile(next);
    yield* writeAtomic(runtime.paths.profile, `${encoded}\n`, 0o600).pipe(
      Effect.catch((error) =>
        pointAtProjection(previousProjection, runtime.paths.scriptLink).pipe(
          Effect.andThen(Effect.fail(error)),
        ),
      ),
    );

    const refreshed = yield* refreshVicinae(runtime.vicinae);
    yield* cleanOldProjections([previousProjection, nextProjection], runtime);
    return { command, refreshed };
  });
}

function runCommand(command: SavedCommand, values: ReadonlyArray<string>, runtime: Runtime) {
  return Effect.gen(function* () {
    const args = yield* commandArguments(command, values);
    const invocation =
      command.execution.type === "argv"
        ? [command.execution.executable, ...args]
        : [runtime.shell, "-c", command.execution.source, "rice-saved-command", ...args];
    return yield* tryPromise(`Cannot run ${command.title}`, async () => {
      const process = Bun.spawn(invocation, {
        ...(command.workingDirectory === undefined ? {} : { cwd: command.workingDirectory }),
        stdin: "inherit",
        stdout: "inherit",
        stderr: "inherit",
      });
      return await process.exited;
    });
  });
}

const program = Effect.gen(function* () {
  const runtime = yield* runtimeFromEnvironment();
  const [operation, ...args] = Bun.argv.slice(2);

  switch (operation) {
    case "create": {
      const result = yield* createCommand(runtime);
      process.stdout.write(`${JSON.stringify(result)}\n`);
      return 0;
    }
    case "list": {
      const profile = yield* loadProfile(runtime.paths.profile);
      process.stdout.write(`${yield* encodeProfile(profile)}\n`);
      return 0;
    }
    case "sync": {
      const profile = yield* loadProfile(runtime.paths.profile);
      yield* synchronizeProjection(profile, runtime);
      yield* refreshVicinae(runtime.vicinae);
      return 0;
    }
    case "run": {
      const separator = args.indexOf("--");
      const id = args[0];
      if (id === undefined || separator !== 1) {
        return yield* Effect.fail(
          new CommandError({
            message: "usage: rice-saved-command run COMMAND_ID -- [PARAMETER ...]",
          }),
        );
      }
      const profile = yield* loadProfile(runtime.paths.profile);
      const command = profile.commands.find((candidate) => candidate.id === id);
      if (command === undefined) {
        return yield* Effect.fail(new CommandError({ message: `Unknown saved-command ID: ${id}` }));
      }
      return yield* runCommand(command, args.slice(separator + 1), runtime);
    }
    default:
      return yield* Effect.fail(
        new CommandError({
          message: "usage: rice-saved-command {create|list|sync|run}",
        }),
      );
  }
});

const exitCode = await Effect.runPromise(
  program.pipe(
    Effect.catch((error) =>
      Effect.sync(() => {
        process.stderr.write(`rice-saved-command: ${error.message}\n`);
        return 64;
      }),
    ),
  ),
);
process.exitCode = exitCode;
