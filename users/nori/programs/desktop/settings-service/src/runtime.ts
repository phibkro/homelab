/* runtime-adapter: fixed Bun process boundaries for immutable builds, activation, and live observation. */
import { readFile, realpath } from "node:fs/promises";
import { Effect, Schema } from "effect";
import {
  ActivationResult,
  BuildResult,
  DesktopSettingsError,
  EvaluationResult,
  GenerationMetadata,
  parseJson,
  type ActiveGeneration,
  type Observation,
} from "./contracts.ts";

type CommandResult = {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
};

type RuntimePaths = {
  readonly builder: string;
  readonly evaluator: string;
  readonly activator: string;
  readonly activeMetadata: string;
  readonly systemctl: string;
  readonly hyprctl: string;
  readonly pkexec: string;
};

const outputLimit = 1024 * 1024;

function summarizeOutput(output: string): string {
  return output.length <= 8192 ? output : `${output.slice(0, 8192)}\n… output truncated`;
}

async function boundedText(stream: ReadableStream<Uint8Array>, commandName: string): Promise<string> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const next = await reader.read();
      if (next.done) break;
      length += next.value.byteLength;
      if (length > outputLimit) {
        throw new DesktopSettingsError("job_failed", `${commandName} exceeded bounded output`);
      }
      chunks.push(next.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

async function command(
  argv: ReadonlyArray<string>,
  environment?: Record<string, string>,
): Promise<CommandResult> {
  let child: Bun.ReadableSubprocess;
  try {
    child =
      environment === undefined
        ? Bun.spawn([...argv], { stdin: "ignore", stdout: "pipe", stderr: "pipe" })
        : Bun.spawn([...argv], {
            stdin: "ignore",
            stdout: "pipe",
            stderr: "pipe",
            env: environment,
          });
  } catch (cause) {
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot start ${argv[0] ?? "command"}: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  try {
    const [exitCode, stdout, stderr] = await Promise.all([
      child.exited,
      boundedText(child.stdout, argv[0] ?? "command"),
      boundedText(child.stderr, argv[0] ?? "command"),
    ]);
    return { exitCode, stdout, stderr };
  } catch (cause) {
    try {
      child.kill();
    } catch {
      // The process can exit while the bounded stream is being drained.
    }
    throw cause;
  }
}

function verifyMetadata(
  metadata: GenerationMetadata,
  source: string,
  revision: number,
  hash: string,
): void {
  if (metadata.source !== source || metadata.profileRevision !== revision || metadata.profileHash !== hash) {
    throw new DesktopSettingsError(
      "activation_rejected",
      "Generation metadata does not match the approved source, revision, and profile hash",
      { expected: { source, revision, hash }, actual: metadata },
    );
  }
}

async function parseOutput<A>(schema: Schema.ConstraintDecoder<A>, text: string, label: string): Promise<A> {
  try {
    return await Effect.runPromise(parseJson(schema, text, label));
  } catch (cause) {
    if (cause instanceof DesktopSettingsError) throw cause;
    throw new DesktopSettingsError(
      "job_failed",
      `Cannot decode ${label}: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
}

export class NixEvaluator {
  readonly paths: RuntimePaths;

  constructor(paths: RuntimePaths) {
    this.paths = paths;
  }

  async preview(profilePath: string, hash: string): Promise<EvaluationResult> {
    const result = await command([
      this.paths.evaluator,
      "--profile",
      profilePath,
      "--profile-hash",
      hash,
    ]);
    if (result.exitCode !== 0) {
      throw new DesktopSettingsError("invalid_profile", "Immutable workstation evaluation failed", {
        exitCode: result.exitCode,
        stderr: summarizeOutput(result.stderr),
      });
    }
    return parseOutput(EvaluationResult, result.stdout, "evaluation result");
  }
}

export class NixBuilder {
  readonly paths: RuntimePaths;

  constructor(paths: RuntimePaths) {
    this.paths = paths;
  }

  async build(
    profilePath: string,
    source: string,
    revision: number,
    hash: string,
  ): Promise<BuildResult> {
    const result = await command([
      this.paths.builder,
      "--profile",
      profilePath,
      "--profile-hash",
      hash,
    ]);
    if (result.exitCode !== 0) {
      throw new DesktopSettingsError("job_failed", "Immutable workstation build failed", {
        exitCode: result.exitCode,
        stderr: summarizeOutput(result.stderr),
      });
    }
    const built = await parseOutput(BuildResult, result.stdout, "build result");
    verifyMetadata(built.metadata, source, revision, hash);
    return built;
  }
}

export class ActivationClient {
  readonly paths: RuntimePaths;

  constructor(paths: RuntimePaths) {
    this.paths = paths;
  }

  async activate(
    profilePath: string,
    artifact: string,
    source: string,
    revision: number,
    hash: string,
  ): Promise<ActiveGeneration> {
    const result = await command([
      this.paths.pkexec,
      this.paths.activator,
      "--operation",
      "org.nori.desktop-settings.activate",
      "--profile",
      profilePath,
      "--artifact",
      artifact,
      "--revision",
      String(revision),
      "--profile-hash",
      hash,
    ]);
    if (result.exitCode !== 0) {
      throw new DesktopSettingsError("activation_rejected", "Privileged activation was rejected", {
        exitCode: result.exitCode,
        stderr: summarizeOutput(result.stderr),
      });
    }
    const activated = await parseOutput(ActivationResult, result.stdout, "activation result");
    verifyMetadata(
      {
        source: activated.activeGeneration.source,
        profileRevision: activated.activeGeneration.profileRevision,
        profileHash: activated.activeGeneration.profileHash,
      },
      source,
      revision,
      hash,
    );
    return activated.activeGeneration;
  }
}

function collectLayerObjects(value: unknown, output: Array<Record<string, unknown>>): void {
  if (Array.isArray(value)) {
    for (const entry of value) collectLayerObjects(entry, output);
    return;
  }
  if (typeof value !== "object" || value === null) return;
  const object = value as Record<string, unknown>;
  output.push(object);
  for (const child of Object.values(object)) collectLayerObjects(child, output);
}

function layerEdge(layers: unknown, monitors: unknown): { edge: "top" | "bottom" } | { reason: string } {
  if (!Array.isArray(monitors) || typeof layers !== "object" || layers === null || Array.isArray(layers)) {
    return { reason: "Hyprland did not return monitor and layer geometry" };
  }
  const layersByMonitor = layers as Record<string, unknown>;
  for (const monitorValue of monitors) {
    if (typeof monitorValue !== "object" || monitorValue === null || Array.isArray(monitorValue)) continue;
    const monitor = monitorValue as Record<string, unknown>;
    const name = monitor.name;
    const monitorY = monitor.y;
    const monitorHeight = monitor.height;
    if (typeof name !== "string" || typeof monitorY !== "number" || typeof monitorHeight !== "number") continue;
    const candidates: Array<Record<string, unknown>> = [];
    collectLayerObjects(layersByMonitor[name], candidates);
    for (const candidate of candidates) {
      const namespace = candidate.namespace;
      if (typeof namespace !== "string" || !namespace.includes("waybar")) continue;
      const geometry =
        typeof candidate.geometry === "object" && candidate.geometry !== null && !Array.isArray(candidate.geometry)
          ? (candidate.geometry as Record<string, unknown>)
          : candidate;
      const y = geometry.y;
      const height = geometry.h ?? geometry.height;
      if (typeof y !== "number" || typeof height !== "number") continue;
      const absoluteY = y >= monitorY && y <= monitorY + monitorHeight ? y : monitorY + y;
      return {
        edge: absoluteY + height / 2 < monitorY + monitorHeight / 2 ? "top" : "bottom",
      };
    }
  }
  return { reason: "No Waybar layer surface is visible in the active Hyprland session" };
}

export class DesktopRuntime {
  readonly paths: RuntimePaths;

  constructor(paths: RuntimePaths) {
    this.paths = paths;
  }

  async reloadWaybar(): Promise<void> {
    const result = await command([this.paths.systemctl, "--user", "reload", "waybar.service"]);
    if (result.exitCode !== 0) {
      throw new DesktopSettingsError("runtime_unavailable", "Cannot reload waybar.service", {
        stderr: summarizeOutput(result.stderr),
      });
    }
  }

  private async hyprlandEnvironment(): Promise<
    { environment: Record<string, string> } | { reason: string }
  > {
    try {
      const result = await command([this.paths.systemctl, "--user", "show-environment"]);
      if (result.exitCode !== 0) {
        return { reason: summarizeOutput(result.stderr) || "systemd user environment is unavailable" };
      }
      const environment: Record<string, string> = {};
      for (const line of result.stdout.split("\n")) {
        const separator = line.indexOf("=");
        if (separator <= 0) continue;
        environment[line.slice(0, separator)] = line.slice(separator + 1);
      }
      if (
        environment.HYPRLAND_INSTANCE_SIGNATURE === undefined ||
        environment.XDG_RUNTIME_DIR === undefined
      ) {
        return { reason: "No active Hyprland session is registered with the user manager" };
      }
      return { environment };
    } catch (cause) {
      return { reason: cause instanceof Error ? cause.message : String(cause) };
    }
  }

  async observe(): Promise<Observation> {
    const unit = await command([
      this.paths.systemctl,
      "--user",
      "show",
      "waybar.service",
      "--property",
      "ActiveState",
      "--value",
    ]);
    const activeState = unit.exitCode === 0 ? unit.stdout.trim() : "unknown";
    if (activeState !== "active") {
      const mapped = activeState === "inactive" || activeState === "failed" ? activeState : "unknown";
      return {
        waybar: {
          unit: mapped,
          edge: "unavailable",
          reason:
            unit.exitCode === 0
              ? `waybar.service is ${activeState || "unavailable"}`
              : summarizeOutput(unit.stderr) || "systemd user manager is unavailable",
        },
      };
    }
    const session = await this.hyprlandEnvironment();
    if ("reason" in session) {
      return { waybar: { unit: "active", edge: "unavailable", reason: session.reason } };
    }
    const [layers, monitors] = await Promise.all([
      command([this.paths.hyprctl, "-j", "layers"], session.environment),
      command([this.paths.hyprctl, "-j", "monitors"], session.environment),
    ]);
    if (layers.exitCode !== 0 || monitors.exitCode !== 0) {
      return {
        waybar: {
          unit: "active",
          edge: "unavailable",
          reason:
            summarizeOutput(layers.stderr || monitors.stderr) ||
            "Hyprland session geometry is unavailable",
        },
      };
    }
    const [layerJson, monitorJson] = await Promise.all([
      parseOutput(Schema.Unknown, layers.stdout, "Hyprland layers"),
      parseOutput(Schema.Unknown, monitors.stdout, "Hyprland monitors"),
    ]);
    const edge = layerEdge(layerJson, monitorJson);
    if ("reason" in edge) {
      return { waybar: { unit: "active", edge: "unavailable", reason: edge.reason } };
    }
    return { waybar: { unit: "active", edge: edge.edge } };
  }

  async activeGeneration(): Promise<ActiveGeneration | undefined> {
    let text: string;
    try {
      text = await readFile(this.paths.activeMetadata, "utf8");
    } catch (cause) {
      if (cause instanceof Error && "code" in cause && cause.code === "ENOENT") return undefined;
      throw new DesktopSettingsError(
        "unavailable",
        `Cannot read active generation metadata: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    }
    const metadata = await parseOutput(GenerationMetadata, text, "active generation metadata");
    let activePath: string;
    try {
      activePath = await realpath("/run/current-system");
    } catch (cause) {
      throw new DesktopSettingsError(
        "unavailable",
        `Cannot resolve active generation: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    }
    let bootDefault = false;
    try {
      const defaultGeneration = await realpath("/nix/var/nix/profiles/system");
      bootDefault = activePath === defaultGeneration;
    } catch {
      // The active metadata remains valid when the boot-default link is unavailable.
    }
    return {
      path: activePath,
      source: metadata.source,
      profileRevision: metadata.profileRevision,
      profileHash: metadata.profileHash,
      bootDefault,
    };
  }
}

export { verifyMetadata as verifyGenerationMetadata };
export type { RuntimePaths };
