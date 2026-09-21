import { components } from "./status.ts";

type Environment = Record<string, string | undefined>;
type Fetcher = typeof fetch;
type CommandRunner = (
  command: string[],
  environment: Environment,
) => Promise<number>;

type Arguments = {
  flags: Map<string, string[]>;
  positionals: string[];
  command: string[];
};

function parseArguments(args: string[]): Arguments {
  const separator = args.indexOf("--");
  const ownArgs = separator === -1 ? args : args.slice(0, separator);
  const command = separator === -1 ? [] : args.slice(separator + 1);
  const flags = new Map<string, string[]>();
  const positionals: string[] = [];
  for (let index = 0; index < ownArgs.length; index += 1) {
    const argument = ownArgs[index]!;
    if (!argument.startsWith("--")) {
      positionals.push(argument);
      continue;
    }
    const name = argument.slice(2);
    const value = ownArgs[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`--${name} requires a value`);
    }
    flags.set(name, [...(flags.get(name) ?? []), value]);
    index += 1;
  }
  return { flags, positionals, command };
}

function flag(args: Arguments, name: string): string | undefined {
  return args.flags.get(name)?.at(-1);
}

function requiredFlag(args: Arguments, name: string): string {
  const value = flag(args, name);
  if (value === undefined) throw new Error(`--${name} is required`);
  return value;
}

function affectedComponents(args: Arguments): string[] {
  return args.flags.get("component") ?? components.map(({ id }) => id);
}

function expectedEnd(args: Arguments, now: Date): string {
  const explicit = flag(args, "expected-end");
  if (explicit !== undefined) return explicit;
  const durationValue = flag(args, "duration-minutes") ?? "120";
  const duration = /^\d+$/.test(durationValue)
    ? Number.parseInt(durationValue, 10)
    : Number.NaN;
  if (!Number.isFinite(duration) || duration <= 0 || duration > 1440) {
    throw new Error("--duration-minutes must be between 1 and 1440");
  }
  return new Date(now.getTime() + duration * 60_000).toISOString();
}

async function mutationToken(environment: Environment): Promise<string> {
  const direct = environment.STATUS_MUTATION_TOKEN?.trim();
  if (direct) return direct;
  const path = environment.STATUS_MUTATION_TOKEN_FILE;
  if (path) {
    const fromFile = (await Bun.file(path).text()).trim();
    if (fromFile) return fromFile;
  }
  throw new Error(
    "set STATUS_MUTATION_TOKEN or STATUS_MUTATION_TOKEN_FILE before mutating status",
  );
}

async function apiRequest(
  path: string,
  body: unknown,
  environment: Environment,
  fetcher: Fetcher,
): Promise<{ id: string }> {
  const token = await mutationToken(environment);
  const baseUrl = (
    environment.STATUS_API_URL ?? "https://status.home.phibkro.org"
  ).replace(/\/$/, "");
  const result = await fetcher(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await result.text();
  let responseBody: { id?: unknown; error?: unknown } = {};
  try {
    responseBody = JSON.parse(text) as typeof responseBody;
  } catch {
    // A non-JSON edge failure is reported by status only, never echoed.
  }
  if (!result.ok) {
    const detail =
      typeof responseBody.error === "string" ? `: ${responseBody.error}` : "";
    throw new Error(`status API returned ${result.status}${detail}`);
  }
  if (typeof responseBody.id !== "string") {
    throw new Error("status API response did not contain an event id");
  }
  return { id: responseBody.id };
}

async function maintenanceStart(
  args: Arguments,
  environment: Environment,
  fetcher: Fetcher,
  now: Date,
): Promise<string> {
  const title = flag(args, "title") ?? "Planned maintenance";
  const result = await apiRequest(
    "/api/operator/events",
    {
      kind: "maintenance",
      title,
      message: flag(args, "message") ?? title,
      components: affectedComponents(args),
      state: "in_progress",
      startsAt: now.toISOString(),
      expectedEndAt: expectedEnd(args, now),
    },
    environment,
    fetcher,
  );
  return result.id;
}

async function maintenanceFinish(
  id: string,
  message: string,
  environment: Environment,
  fetcher: Fetcher,
): Promise<void> {
  await apiRequest(
    `/api/operator/events/${encodeURIComponent(id)}/updates`,
    { state: "completed", message },
    environment,
    fetcher,
  );
}

export function withoutStatusSecrets(environment: Environment): Environment {
  const childEnvironment = { ...process.env, ...environment };
  delete childEnvironment.STATUS_MUTATION_TOKEN;
  delete childEnvironment.STATUS_MUTATION_TOKEN_FILE;
  return childEnvironment;
}

const runCommand: CommandRunner = async (command, environment) => {
  const child = Bun.spawn(command, {
    cwd: process.cwd(),
    env: environment,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  return child.exited;
};

export async function runStatusctl(
  argv: string[],
  environment: Environment = process.env,
  fetcher: Fetcher = fetch,
  now: () => Date = () => new Date(),
  commandRunner: CommandRunner = runCommand,
): Promise<number> {
  const [command, ...rest] = argv;
  if (command === undefined) throw new Error("statusctl command is required");
  const args = parseArguments(rest);

  if (command === "maintenance-start") {
    console.log(await maintenanceStart(args, environment, fetcher, now()));
    return 0;
  }
  if (command === "maintenance-finish") {
    const id = args.positionals[0];
    if (id === undefined) throw new Error("maintenance-finish requires an id");
    await maintenanceFinish(
      id,
      flag(args, "message") ?? "Maintenance completed",
      environment,
      fetcher,
    );
    return 0;
  }
  if (command === "incident-start") {
    const result = await apiRequest(
      "/api/operator/events",
      {
        kind: "incident",
        title: requiredFlag(args, "title"),
        impact: flag(args, "impact") ?? "outage",
        message: requiredFlag(args, "message"),
        components: affectedComponents(args),
        state: "investigating",
      },
      environment,
      fetcher,
    );
    console.log(result.id);
    return 0;
  }
  if (command === "incident-update") {
    const id = args.positionals[0];
    if (id === undefined) throw new Error("incident-update requires an id");
    await apiRequest(
      `/api/operator/events/${encodeURIComponent(id)}/updates`,
      {
        state: requiredFlag(args, "state"),
        message: requiredFlag(args, "message"),
      },
      environment,
      fetcher,
    );
    return 0;
  }
  if (command === "maintained") {
    if (args.command.length === 0) {
      throw new Error("maintained requires a command after --");
    }
    const id = await maintenanceStart(args, environment, fetcher, now());
    console.error(`maintenance ${id} opened`);
    const exitCode = await commandRunner(
      args.command,
      withoutStatusSecrets(environment),
    );
    if (exitCode !== 0) {
      console.error(
        `command failed with ${exitCode}; maintenance ${id} remains open`,
      );
      return exitCode;
    }
    try {
      await maintenanceFinish(
        id,
        "Maintenance completed successfully",
        environment,
        fetcher,
      );
      console.error(`maintenance ${id} completed`);
      return 0;
    } catch (error) {
      console.error(
        `command succeeded but maintenance ${id} remains open: ${error instanceof Error ? error.message : "unknown status API failure"}`,
      );
      return 1;
    }
  }

  throw new Error(`unknown statusctl command: ${command}`);
}

if (import.meta.main) {
  try {
    process.exitCode = await runStatusctl(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : "statusctl failed");
    process.exitCode = 64;
  }
}
