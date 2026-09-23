/* composition-root: reads process configuration once and selects Bun adapters. */
import { startIpcServer } from "./daemon.ts";
import { runRuntimeObservation, runSettingsCli } from "./cli.ts";
import { DesktopSettingsError } from "./contracts.ts";
import { acquireAuthorityLock } from "./authority-lock.ts";
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
    activeMetadata: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_ACTIVE_METADATA",
      "/etc/nori-desktop-settings/generation.json",
    ),
    systemctl: pathEnvironment("NORI_DESKTOP_SETTINGS_SYSTEMCTL", "systemctl"),
    hyprctl: pathEnvironment("NORI_DESKTOP_SETTINGS_HYPRCTL", "hyprctl"),
    authorityLock: pathEnvironment(
      "NORI_DESKTOP_SETTINGS_AUTHORITY_LOCK",
      "/run/lock/nori-desktop-settings-activation.lock",
    ),
    flock: pathEnvironment("NORI_DESKTOP_SETTINGS_FLOCK", "flock"),
  };
}
async function runDaemon(): Promise<number> {
  const config = serviceConfig();
  const releaseDaemonLock = await acquireDaemonLock(config.stateHome);
  try {
    const releaseAuthorityLock = await acquireAuthorityLock(config);
    let service: DesktopSettingsService;
    try {
      service = await DesktopSettingsService.make(config);
    } finally {
      await releaseAuthorityLock();
    }
    const socket = pathEnvironment(
      "NORI_DESKTOP_SETTINGS_SOCKET",
      "/run/nori-desktop-settings/backend.sock",
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
    await releaseDaemonLock();
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
} else if (operation === "observe-runtime") {
  process.exitCode = await runRuntimeObservation(args, serviceConfig());
} else {
  process.exitCode = await runSettingsCli([operation, ...args].filter((value): value is string => value !== undefined));
}
