import { basename, isAbsolute } from "node:path";
import { Effect, Schema } from "effect";

export const outputModes = ["fullOutput", "compact", "silent", "inline", "terminal"] as const;

const Parameter = Schema.Struct({
  name: Schema.String,
  optional: Schema.Boolean,
});

const ArgvExecution = Schema.Struct({
  type: Schema.Literal("argv"),
  executable: Schema.String,
  arguments: Schema.Array(Schema.String),
});

const ShellExecution = Schema.Struct({
  type: Schema.Literal("shell"),
  source: Schema.String,
});

export const CreateCommandRequest = Schema.Struct({
  title: Schema.String,
  outputMode: Schema.Literals(outputModes),
  workingDirectory: Schema.optionalKey(Schema.String),
  parameters: Schema.Array(Parameter),
  execution: Schema.Union([ArgvExecution, ShellExecution]),
});

export const SavedCommand = Schema.Struct({
  id: Schema.String,
  title: Schema.String,
  outputMode: Schema.Literals(outputModes),
  workingDirectory: Schema.optionalKey(Schema.String),
  parameters: Schema.Array(Parameter),
  execution: Schema.Union([ArgvExecution, ShellExecution]),
});

export const SavedCommandProfile = Schema.Struct({
  version: Schema.Literal(1),
  revision: Schema.Number,
  commands: Schema.Array(SavedCommand),
});

export type CreateCommandRequest = typeof CreateCommandRequest.Type;
export type SavedCommand = typeof SavedCommand.Type;
export type SavedCommandProfile = typeof SavedCommandProfile.Type;

export class CommandError extends Schema.TaggedError<CommandError>()("CommandError", {
  message: Schema.String,
}) {}

const strictParseOptions = {
  errors: "all",
  onExcessProperty: "error",
} as const;
const privilegedExecutables: Record<string, true> = {
  doas: true,
  pkexec: true,
  run0: true,
  su: true,
  sudo: true,
  sudoedit: true,
};

const parameterNamePattern = /^[a-z][a-z0-9-]*$/;
const placeholderPattern = /\{\{([a-z][a-z0-9-]*)\}\}/g;
const oneLinePattern = /^[^\r\n]+$/;

const fail = (message: string) => Effect.fail(new CommandError({ message }));

export const decodeCreateRequest = (input: unknown) =>
  Schema.decodeUnknownEffect(
    CreateCommandRequest,
    strictParseOptions,
  )(input).pipe(
    Effect.mapError((error) => new CommandError({ message: `Invalid create request: ${error}` })),
    Effect.flatMap(validateCreateRequest),
  );

export const decodeProfile = (input: unknown) =>
  Schema.decodeUnknownEffect(
    SavedCommandProfile,
    strictParseOptions,
  )(input).pipe(
    Effect.mapError(
      (error) => new CommandError({ message: `Invalid saved-command profile: ${error}` }),
    ),
    Effect.flatMap(validateProfile),
  );

function validateCreateRequest(request: CreateCommandRequest) {
  return Effect.gen(function* () {
    const title = request.title.trim();
    if (!oneLinePattern.test(title)) {
      return yield* fail("Title must be one non-empty line");
    }
    if (request.parameters.length > 3) {
      return yield* fail("A command can declare at most three parameters");
    }

    const parameterNames = new Set<string>();
    let optionalSeen = false;
    for (const parameter of request.parameters) {
      if (!parameterNamePattern.test(parameter.name)) {
        return yield* fail(
          `Invalid parameter name ${JSON.stringify(parameter.name)}; use lower-case letters, digits, and hyphens`,
        );
      }
      if (parameterNames.has(parameter.name)) {
        return yield* fail(`Duplicate parameter name: ${parameter.name}`);
      }
      if (!parameter.optional && optionalSeen) {
        return yield* fail("Required parameters must precede optional parameters");
      }
      optionalSeen ||= parameter.optional;
      parameterNames.add(parameter.name);
    }

    if (request.workingDirectory !== undefined && !isAbsolute(request.workingDirectory)) {
      return yield* fail("Working directory must be an absolute path");
    }

    if (request.execution.type === "argv") {
      const executable = request.execution.executable.trim();
      if (executable.length === 0 || /[\r\n]/.test(executable)) {
        return yield* fail("Executable must be one non-empty line");
      }
      if (!isAbsolute(executable) && /\s/.test(executable)) {
        return yield* fail(
          "Executable must be one command name; put each argument on its own line",
        );
      }
      if (privilegedExecutables[basename(executable).toLowerCase()] === true) {
        return yield* fail(`${basename(executable)} is a privilege wrapper and is not allowed`);
      }

      const referenced = new Set<string>();
      for (const argument of request.execution.arguments) {
        for (const match of argument.matchAll(placeholderPattern)) {
          const name = match[1];
          if (name !== undefined) referenced.add(name);
        }
      }
      for (const name of referenced) {
        if (!parameterNames.has(name)) {
          return yield* fail(`Argument references unknown parameter: ${name}`);
        }
      }
      for (const name of parameterNames) {
        if (!referenced.has(name)) {
          return yield* fail(`Parameter is not used by an argument: ${name}`);
        }
      }

      return {
        ...request,
        title,
        execution: { ...request.execution, executable },
      } satisfies CreateCommandRequest;
    }

    if (request.execution.source.trim().length === 0) {
      return yield* fail("Shell source must not be empty");
    }
    return { ...request, title } satisfies CreateCommandRequest;
  });
}

function validateProfile(profile: SavedCommandProfile) {
  return Effect.gen(function* () {
    if (!Number.isSafeInteger(profile.revision) || profile.revision < 0) {
      return yield* fail("Profile revision must be a non-negative integer");
    }
    const ids = new Set<string>();
    for (const command of profile.commands) {
      if (!/^user\.[a-z0-9]+(?:[.-][a-z0-9]+)*$/.test(command.id)) {
        return yield* fail(`Invalid saved-command ID: ${command.id}`);
      }
      if (ids.has(command.id)) {
        return yield* fail(`Duplicate saved-command ID: ${command.id}`);
      }
      ids.add(command.id);
      yield* validateCreateRequest(command);
    }
    return profile;
  });
}

export function makeSavedCommand(
  request: CreateCommandRequest,
  idSuffix = crypto.randomUUID().slice(0, 8),
): SavedCommand {
  const slug =
    request.title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "") || "command";
  return { ...request, id: `user.${slug}.${idSuffix.toLowerCase()}` };
}

export function commandArguments(
  command: SavedCommand,
  values: ReadonlyArray<string>,
): Effect.Effect<ReadonlyArray<string>, CommandError> {
  const required = command.parameters.filter((parameter) => !parameter.optional).length;
  if (values.length < required || values.length > command.parameters.length) {
    return fail(
      `Expected ${required === command.parameters.length ? required : `${required}-${command.parameters.length}`} parameters, received ${values.length}`,
    );
  }

  const byName = new Map(
    command.parameters.map((parameter, index) => [parameter.name, values[index] ?? ""]),
  );

  if (command.execution.type === "shell") return Effect.succeed(values);
  return Effect.succeed(
    command.execution.arguments.map((argument) =>
      argument.replace(placeholderPattern, (_, name: string) => byName.get(name) ?? ""),
    ),
  );
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

export function renderScript(command: SavedCommand, runner: string, shell: string): string {
  const directives = command.parameters.map(
    (parameter, index) =>
      `# @vicinae.argument${index + 1} ${JSON.stringify({ type: "text", placeholder: parameter.name, optional: parameter.optional })}`,
  );
  return [
    `#!${shell}`,
    "# @vicinae.schemaVersion 1",
    `# @vicinae.title ${command.title}`,
    `# @vicinae.mode ${command.outputMode}`,
    "# @vicinae.description User saved command",
    '# @vicinae.keywords ["saved", "user"]',
    ...directives,
    "",
    `exec ${shellQuote(runner)} run ${shellQuote(command.id)} -- \"$@\"`,
    "",
  ].join("\n");
}
