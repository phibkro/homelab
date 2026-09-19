import { expect, it } from "bun:test";
import { mkdtemp, chmod, writeFile, rm, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const guest = join(import.meta.dir, "../infra/workstation/firecracker-environment-guest.ts");
const request = (generation = "shg_demo", requestId = "req-1", ordinal = 1) =>
  `${JSON.stringify({
    _tag: "SelfHostedGuestRpcRequest",
    environmentId: "demo",
    generation: { generationId: generation, ordinal },
    requestId,
    operation: "get_state",
    payload: {},
  })}\n`;

const runGuest = async (omp: string, input: string, generation = "shg_demo") => {
  const directory = await mkdtemp(join(tmpdir(), "adlc-guest-test-"));
  const executable = join(directory, "omp");
  await writeFile(executable, `#!/bin/sh\n${omp}\n`);
  await chmod(executable, 0o755);
  const entrypoint = join(directory, "entry.ts");
  await writeFile(
    entrypoint,
    `import { runGuestRpc } from ${JSON.stringify(guest)};\nawait runGuestRpc(() => ({ source: "test-isolation" }));\n`,
  );
  const child = Bun.spawn(["bun", entrypoint], {
    stdin: new Blob([input]),
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...process.env,
      ADLC_GENERATION: generation,
      ADLC_GENERATION_ORDINAL: "1",
      ADLC_GUEST_RPC_TIMEOUT_MS: "10000",
      PATH: `${directory}:${process.env.PATH}`,
    },
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  await rm(directory, { recursive: true, force: true });
  return { exitCode, stdout, stderr };
};

it("correlates the exact ready and get_state OMP data frame", async () => {
  const result = await runGuest(
    `printf '%s\\n' '{"type":"ready"}'\nread line\nprintf '%s\\n' '{"type":"response","id":"req-1","command":"get_state","success":true,"data":{"answer":42}}'`,
    request(),
  );
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toMatchObject({
    _tag: "SelfHostedGuestRpcResponse",
    requestId: "req-1",
    operation: "get_state",
    stateJson: '{"omp":{"answer":42},"isolation":{"source":"test-isolation"}}',
  });
});

it("rejects a stale generation before starting a guest request", async () => {
  const result = await runGuest(`printf '%s\\n' '{"type":"ready"}'`, request("shg_stale"));
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("generation mismatch");
});
it("rejects a wrong generation ordinal before starting OMP", async () => {
  const marker = join(tmpdir(), `adlc-guest-ordinal-${String(process.pid)}`);
  const result = await runGuest(
    `touch ${marker}\nprintf '%s\\n' '{"type":"ready"}'`,
    request("shg_demo", "req-1", 2),
  );
  await expect(access(marker)).rejects.toThrow();
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("generation mismatch");
});

it("rejects an unsuccessful correlated OMP response", async () => {
  const result = await runGuest(
    `printf '%s\\n' '{"type":"ready"}'\nread line\nprintf '%s\\n' '{"type":"response","id":"req-1","command":"get_state","success":false}'`,
    request(),
  );
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("OMP get_state failed");
});
it("times out when OMP never emits a ready frame", async () => {
  const result = await runGuest("sleep 11", request());
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("OMP RPC timed out");
}, 15_000);

it("requires the strict OMP data response field", async () => {
  const result = await runGuest(
    `printf '%s\\n' '{"type":"ready"}'\nread line\nprintf '%s\\n' '{"type":"response","id":"req-1","command":"get_state","success":true,"stateJson":"{}"}'`,
    request(),
  );
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("OMP get_state failed");
});

it("rejects an oversized correlated state response", async () => {
  const result = await runGuest(
    `printf '%s\\n' '{"type":"ready"}'\nread line\nprintf '%s\\n' '{"type":"response","id":"req-1","command":"get_state","success":true,"data":"'$(head -c 786433 /dev/zero | base64 -w 0)'"}'`,
    request(),
  );
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("OMP RPC frame exceeds limit");
});
