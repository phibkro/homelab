import { afterEach, expect, test } from "bun:test";
import { chmod, mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const temporaryDirectories: string[] = [];

function quoteShell(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "rice-saved-command-"));
  temporaryDirectories.push(root);
  const runner = join(root, "rice-saved-command");
  const shell = process.env.TEST_SHELL ?? "/bin/sh";
  const main = join(import.meta.dir, "..", "src", "main.ts");
  await Bun.write(
    runner,
    `#!${shell}\nexport RICE_SAVED_COMMAND_BIN=${quoteShell(runner)}\nexport RICE_SAVED_COMMAND_SHELL=${quoteShell(shell)}\nexec ${quoteShell(process.execPath)} ${quoteShell(main)} "$@"\n`,
  );
  await chmod(runner, 0o755);
  const env = {
    ...process.env,
    HOME: root,
    XDG_CONFIG_HOME: join(root, "config"),
    XDG_DATA_HOME: join(root, "data"),
  };
  return { env, root, runner, shell };
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

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) => rm(path, { force: true, recursive: true })),
  );
});

test("saved argv parameters remain one literal argument and survive processes", async () => {
  const { env, root, runner, shell } = await fixture();
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
  const result = JSON.parse(created.stdout) as {
    command: { id: string };
  };
  const scriptDirectory = join(root, "data", "vicinae", "scripts", "nori-saved");
  const [scriptName] = await readdir(scriptDirectory);
  expect(scriptName).toBeDefined();
  const scriptPath = join(scriptDirectory, scriptName!);
  const script = await Bun.file(scriptPath).text();
  expect(script).toContain(
    '# @vicinae.argument1 {"type":"text","placeholder":"message","optional":false}',
  );

  const ran = await invoke(scriptPath, env, [literal]);
  expect(ran.status).toBe(0);
  expect(ran.stdout).toBe(`${literal}\n`);
  expect(await Bun.file(marker).exists()).toBe(false);

  const listed = await invoke(runner, env, ["list"]);
  expect(listed.status).toBe(0);
  expect(listed.stdout).toContain(result.command.id);
});

test("saved command preserves stderr and nonzero status", async () => {
  const { env, runner, shell, root } = await fixture();
  const request = {
    title: "Expected failure",
    outputMode: "fullOutput",
    parameters: [],
    execution: {
      type: "argv",
      executable: shell,
      arguments: ["-c", "printf 'expected failure' >&2; exit 23"],
    },
  };

  const created = await invoke(runner, env, ["create"], JSON.stringify(request));
  expect(created.status).toBe(0);
  const [scriptName] = await readdir(join(root, "data", "vicinae", "scripts", "nori-saved"));
  const ran = await invoke(
    join(root, "data", "vicinae", "scripts", "nori-saved", scriptName!),
    env,
    [],
  );
  expect(ran.status).toBe(23);
  expect(ran.stderr).toContain("expected failure");
});

test("argv mode rejects direct privilege wrappers", async () => {
  const { env, runner } = await fixture();
  for (const executable of ["doas", "pkexec", "run0", "su", "sudo", "sudoedit"]) {
    const request = {
      title: "Forbidden",
      outputMode: "fullOutput",
      parameters: [],
      execution: { type: "argv", executable, arguments: ["true"] },
    };
    const result = await invoke(runner, env, ["create"], JSON.stringify(request));
    expect(result.status).toBe(64);
    expect(result.stderr).toContain("privilege wrapper");
  }
});

test("explicit shell mode receives positional parameters", async () => {
  const { env, runner, root } = await fixture();
  const request = {
    title: "Explicit shell",
    outputMode: "fullOutput",
    parameters: [{ name: "message", optional: false }],
    execution: { type: "shell", source: 'printf "%s\\n" "$1"' },
  };
  const created = await invoke(runner, env, ["create"], JSON.stringify(request));
  expect(created.status).toBe(0);
  const [scriptName] = await readdir(join(root, "data", "vicinae", "scripts", "nori-saved"));
  const ran = await invoke(
    join(root, "data", "vicinae", "scripts", "nori-saved", scriptName!),
    env,
    ["shell parameter"],
  );
  expect(ran.status).toBe(0);
  expect(ran.stdout).toBe("shell parameter\n");
});

test("argv mode rejects shell source as an executable", async () => {
  const { env, runner } = await fixture();
  const request = {
    title: "Implicit shell",
    outputMode: "fullOutput",
    parameters: [],
    execution: {
      type: "argv",
      executable: 'printf "%s\\n" "$1"',
      arguments: [],
    },
  };
  const result = await invoke(runner, env, ["create"], JSON.stringify(request));
  expect(result.status).toBe(64);
  expect(result.stderr).toContain("one command name");
});
