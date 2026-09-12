/* composition-root: reads process configuration once and selects Bun adapters. */
import { startIpcServer } from "./daemon.ts";
import { runSettingsCli } from "./cli.ts";
import { DesktopSettingsError } from "./contracts.ts";
import { acquireDaemonLock } from "./daemon-lock.ts";
import { DesktopSettingsService, type ServiceConfig } from "./service.ts";

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (value === undefined || value.length === 0) {
    throw new DesktopSettingsError("unavailable", `${name} is not configured`);
  }
  return value;
}

function pathEnvironment(name: string, fallback: string): string {
  const value = process.env[name];
  return value === undefined || value.length === 0 ? fallback : value;
}

function serviceConfig(): ServiceConfig {
  const home = requiredEnvironment("HOME");
  const configHome = pathEnvironment("XDG_CONFIG_HOME", `${home}/.config`);
  const stateHome = pathEnvironment("XDG_STATE_HOME", `${home}/.local/state`);
  const dataHome = pathEnvironment("XDG_DATA_HOME", `${home}/.local/share`);
  const runtimeDirectory = requiredEnvironment("XDG_RUNTIME_DIR");
  return {
    configHome: pathEnvironment("NORI_DESKTOP_SETTINGS_CONFIG_HOME", `${configHome}/nori-desktop`),
    stateHome: pathEnvironment("NORI_DESKTOP_SETTINGS_STATE_HOME", `${stateHome}/nori-desktop`),
    dataDirectory: pathEnvironment("NORI_DESKTOP_SETTINGS_DATA_DIR", `${dataHome}/nori-desktop`),
    approvedSource: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_APPROVED_SOURCE",
      "/etc/nori-desktop-settings/approved-source.json",
    ),
    riceCommand: pathEnvironment("NORI_DESKTOP_SETTINGS_RICE_COMMAND", "rice-saved-command"),
    shell: pathEnvironment("NORI_DESKTOP_SETTINGS_SHELL", "/bin/sh"),
    builder: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_BUILDER",
      "/run/current-system/sw/bin/nori-desktop-settings-build",
    ),
    evaluator: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_EVALUATOR",
      "/run/current-system/sw/bin/nori-desktop-settings-preview",
    ),
    activator: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_ACTIVATOR",
      "/run/current-system/sw/bin/nori-desktop-settings-activate",
    ),
    activeMetadata: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_ACTIVE_METADATA",
      "/etc/nori-desktop-settings/generation.json",
    ),
    systemctl: pathEnvironment("NORI_DESKTOP_SETTINGS_SYSTEMCTL", "systemctl"),
    hyprctl: pathEnvironment("NORI_DESKTOP_SETTINGS_HYPRCTL", "hyprctl"),
    pkexec: pathEnvironment("NORI_DESKTOP_SETTINGS_PKEXEC", "pkexec"),
  };
}


async function runDaemon(): Promise<number> {
  const config = serviceConfig();
  const releaseLock = await acquireDaemonLock(config.stateHome);
  try {
    const service = await DesktopSettingsService.make(config);
    const socket = pathEnvironment(
      "NORI_DESKTOP_SETTINGS_SOCKET",
      "/run/nori-desktop-settings/settings.sock",
    );
    const server = await startIpcServer(service, socket);
    const { promise, resolve } = Promise.withResolvers<void>();
    const stop = () => {
      server.stop(true);
      resolve();
    };
    process.once("SIGINT", stop);
    process.once("SIGTERM", stop);
    await promise;
  } finally {
    await releaseLock();
  }
  return 0;
}

const [operation, ...args] = Bun.argv.slice(2);
if (operation === "daemon") {
  try {
    process.exitCode = await runDaemon();
  } catch (cause) {
    const error =
      cause instanceof DesktopSettingsError
        ? cause
        : new DesktopSettingsError("unavailable", cause instanceof Error ? cause.message : String(cause));
    process.stderr.write(`nori-desktop-config: ${error.message}\n`);
    process.exitCode = 1;
  }
} else {
  process.exitCode = await runSettingsCli([operation, ...args].filter((value): value is string => value !== undefined));
}
