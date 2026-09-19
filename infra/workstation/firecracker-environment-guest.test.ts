import { describe, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

const guest = join(import.meta.dir, "firecracker-environment-guest.ts");

describe("generation-bound guest RPC", () => {
  test("responds while request stdin remains open", async () => {
    const dir = mkdtempSync(join(tmpdir(), "adlc-guest-test-"));
    const omp = join(dir, "omp");
    writeFileSync(
      omp,
      `#!/bin/sh
printf '%s\\n' '{"type":"ready"}'
while IFS= read -r line; do
  printf '%s\\n' '{"id":"test-request","type":"response","command":"get_state","success":true,"data":{"ready":true}}'
done
`,
    );
    chmodSync(omp, 0o755);
    const entrypoint = join(dir, "entry.ts");
    writeFileSync(
      entrypoint,
      `import { runGuestRpc } from ${JSON.stringify(guest)};\nawait runGuestRpc(() => ({ source: "test-isolation" }));\n`,
    );
    const child = spawn(process.execPath, [entrypoint], {
      env: {
        ...process.env,
        ADLC_GENERATION: "shg_demo",
        ADLC_GENERATION_ORDINAL: "1",
        PATH: `${dir}:${process.env.PATH}`,
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk.toString()));
    child.stderr.on("data", (chunk) => (stderr += chunk.toString()));
    try {
      child.stdin.write(
        `${JSON.stringify({
          _tag: "SelfHostedGuestRpcRequest",
          environmentId: "test-environment",
          generation: { generationId: "shg_demo", ordinal: 1 },
          requestId: "test-request",
          operation: "get_state",
          payload: {},
        })}\n`,
      );
      const response = await new Promise<Record<string, unknown>>((resolve, reject) => {
        // This subprocess integration test needs a bound for a broken guest.
        const timer = setTimeout(
          () => reject(new Error(`guest response timed out: ${stderr}`)),
          5_000,
        );
        const check = () => {
          const line = stdout
            .split("\n")
            .find((value) => value.includes("SelfHostedGuestRpcResponse"));
          if (!line) return;
          clearTimeout(timer);
          resolve(JSON.parse(line) as Record<string, unknown>);
        };
        child.stdout.on("data", check);
        check();
      });
      expect(response).toMatchObject({
        _tag: "SelfHostedGuestRpcResponse",
        requestId: "test-request",
        operation: "get_state",
        stateJson: JSON.stringify({
          omp: { ready: true },
          isolation: { source: "test-isolation" },
        }),
      });
      expect(child.exitCode).toBeNull();
    } finally {
      child.kill("SIGTERM");
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
