/* runtime-adapter: hold the root-owned activation flock across one authority mutation. */
import { DesktopSettingsError } from "./contracts.ts";

export type AuthorityLockPaths = {
  readonly authorityLock: string;
  readonly shell: string;
  readonly flock: string;
};

export async function acquireAuthorityLock(paths: AuthorityLockPaths): Promise<() => Promise<void>> {
  let child: Bun.ReadableSubprocess;
  try {
    child = Bun.spawn([paths.flock, "-x", paths.authorityLock, paths.shell, "-c", "printf 1; read -r _"], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch (cause) {
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot start authority lock: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }

  const reader = child.stdout.getReader();
  const ready = await reader.read();
  if (ready.done || new TextDecoder().decode(ready.value) !== "1") {
    const stderr = await new Response(child.stderr).text();
    throw new DesktopSettingsError("unavailable", `Cannot acquire authority lock: ${stderr.trim()}`);
  }

  return async () => {
    reader.releaseLock();
    (child.stdin as { end(): void } | undefined)?.end();
    await child.exited;
  };
}

export async function withAuthorityLock<A>(
  paths: AuthorityLockPaths,
  operation: () => Promise<A>,
): Promise<A> {
  const release = await acquireAuthorityLock(paths);
  try {
    return await operation();
  } finally {
    await release();
  }
}
