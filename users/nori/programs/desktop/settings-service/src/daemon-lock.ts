/* runtime-adapter: exclusive daemon ownership before any mutable service initialization. */
import { mkdir, open, readFile, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { DesktopSettingsError } from "./contracts.ts";

async function processStartTime(pid: number): Promise<string | undefined> {
  const stat = await readFile(`/proc/${pid}/stat`, "utf8").catch(() => undefined);
  if (stat === undefined) return undefined;
  const fields = stat.slice(stat.lastIndexOf(")") + 2).trim().split(/\s+/);
  return fields[19];
}

export async function acquireDaemonLock(stateHome: string): Promise<() => Promise<void>> {
  const path = join(stateHome, "daemon.lock");
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const startTime = await processStartTime(process.pid);
  if (startTime === undefined) {
    throw new DesktopSettingsError("unavailable", "Cannot establish daemon process identity");
  }
  try {
    const handle = await open(path, "wx", 0o600);
    try {
      await handle.writeFile(JSON.stringify({ pid: process.pid, startTime }), "utf8");
      await handle.sync();
    } finally {
      await handle.close();
    }
  } catch (cause) {
    if (!(cause instanceof Error && "code" in cause && cause.code === "EEXIST")) throw cause;
    const existing = JSON.parse(await readFile(path, "utf8").catch(() => "{}")) as {
      pid?: unknown;
      startTime?: unknown;
    };
    const pid = existing.pid;
    const existingStartTime = existing.startTime;
    if (typeof pid !== "number" || !Number.isSafeInteger(pid) || typeof existingStartTime !== "string") {
      throw new DesktopSettingsError("unavailable", "Settings daemon lock is incomplete; refusing a concurrent start");
    }
    if ((await processStartTime(pid)) === existingStartTime) {
      throw new DesktopSettingsError("unavailable", "nori-desktop-config is already running");
    }
    await rm(path, { force: true });
    return acquireDaemonLock(stateHome);
  }
  return () => rm(path, { force: true });
}
