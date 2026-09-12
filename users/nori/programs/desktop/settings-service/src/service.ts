/* application: serialized profile mutations and durable apply orchestration. */
import { readFile } from "node:fs/promises";
import { withAuthorityLock } from "./authority-lock.ts";
import { Effect, Schema } from "effect";
import {
  DesktopSettingsError,
  assertNonNegativeSafeInteger,
  parseJson,
  type ActiveGeneration,
  type AuthorizationFailureRequest,
  type ApplyJob,
  type ApplyRequest,
  type ChangeRequest,
  type CreateSavedCommandRequest,
  type GenerationMetadata,
  type Observation,
  type ReconcileRequest,
  type PreviewRequest,
  type Profile,
  type SavedCommandLookupRequest,
} from "./contracts.ts";
import { JobStore, PreviewStore, ProfileStore, ResolvedStore, type StoredProfile } from "./files.ts";
import {
  DesktopRuntime,
  NixBuilder,
  NixEvaluator,
  type RuntimePaths,
} from "./runtime.ts";
import { maxFrameBytes } from "./framing.ts";
import { SchemaCatalog } from "./schema-catalog.ts";
import {
  decodeCreateRequest,
  lookupSavedCommand,
  makeSavedCommand,
  renderProjection,
  type SavedCommand,
  type SavedCommandProjection,
} from "./saved-command.ts";

type ApprovedSource = {
  readonly source: string;
  readonly host: string;
};

export type ServiceConfig = RuntimePaths & {
  readonly configHome: string;
  readonly stateHome: string;
  readonly dataDirectory: string;
  readonly approvedSource: string;
  readonly riceCommand: string;
  readonly shell: string;
  readonly authorityLock: string;
  readonly flock: string;
};

export type ServiceState = {
  readonly profile: Profile;
  readonly components: Record<string, unknown>;
  readonly resolved: Record<string, unknown>;
  readonly resolvedIdentity: GenerationMetadata | null;
  readonly committedPreviewId: string | null;
  readonly contracts: {
    readonly inputSchema: Record<string, unknown>;
    readonly outputSchema: Record<string, unknown>;
  };
  readonly activeGeneration: ActiveGeneration | null;
  readonly observed: Observation;
  readonly jobs: ReadonlyArray<ApplyJob>;
};

export type SettingsPreview = {
  readonly id: string;
  readonly profile: Profile;
  readonly profileHash: string;
  readonly identity: GenerationMetadata;
  readonly artifact: string;
  readonly resolved: Record<string, unknown>;
  readonly impact: {
    readonly applyClass: string;
    readonly requiresGeneration: boolean;
  };
};

class MutationCoordinator {
  private tail: Promise<void> = Promise.resolve();

  async run<A>(operation: () => Promise<A>): Promise<A> {
    const previous = this.tail;
    let release: (() => void) | undefined;
    this.tail = new Promise<void>((resolve) => {
      release = resolve;
    });
    await previous;
    try {
      return await operation();
    } finally {
      release?.();
    }
  }
}

function unavailableObservation(cause: unknown): Observation {
  return {
    waybar: {
      unit: "unknown",
      edge: "unavailable",
      reason: cause instanceof Error ? cause.message : String(cause),
    },
  };
}

function failure(cause: unknown): { readonly code: string; readonly message: string; readonly details?: unknown } {
  if (cause instanceof DesktopSettingsError) {
    return cause.details === undefined
      ? { code: cause.code, message: cause.message }
      : { code: cause.code, message: cause.message, details: cause.details };
  }
  return {
    code: "job_failed",
    message: cause instanceof Error ? cause.message : String(cause),
  };
}

function appendLog(job: ApplyJob, message: string): ApplyJob {
  return {
    ...job,
    updatedAt: new Date().toISOString(),
    log: [...job.log, message].slice(-16),
  };
}

function expectedRevision(current: StoredProfile, expected: number): void {
  assertNonNegativeSafeInteger(expected, "Expected revision");
  if (current.profile.revision !== expected) {
    throw new DesktopSettingsError("revision_conflict", "Profile revision no longer matches", {
      expected,
      actual: current.profile.revision,
    });
  }
}

export class DesktopSettingsService {
  readonly config: ServiceConfig;
  readonly catalog: SchemaCatalog;
  readonly profiles: ProfileStore;
  readonly resolved: ResolvedStore;
  readonly previews: PreviewStore;
  readonly jobs: JobStore;
  readonly builder: NixBuilder;
  readonly evaluator: NixEvaluator;
  readonly desktop: DesktopRuntime;
  readonly coordinator = new MutationCoordinator();
  readonly running = new Map<string, Promise<ApplyJob>>();
  private applyTail: Promise<void> = Promise.resolve();

  private constructor(config: ServiceConfig, catalog: SchemaCatalog) {
    this.config = config;
    this.catalog = catalog;
    this.profiles = new ProfileStore(config.configHome, config.stateHome);
    this.resolved = new ResolvedStore(config.stateHome);
    this.previews = new PreviewStore(config.stateHome);
    this.jobs = new JobStore(config.stateHome);
    this.builder = new NixBuilder(config);
    this.desktop = new DesktopRuntime(config);
    this.evaluator = new NixEvaluator(config);
  }

  static async make(config: ServiceConfig): Promise<DesktopSettingsService> {
    const catalog = await SchemaCatalog.load(config.dataDirectory);
    const service = new DesktopSettingsService(config, catalog);
    const profile = await service.profiles.initialize(catalog.initialComponents());
    catalog.validateComponents(profile.profile.components);
    await service.resolved.initialize();
    await service.previews.initialize();
    const source = await service.approvedSource().catch(() => undefined);
    if (source !== undefined) {
      await service.previews.recoverCommitted(source.source, profile.profile.revision, profile.hash);
    }
    await service.jobs.initialize();
    const interrupted = await service.jobs.recoverInterrupted();
    if (interrupted.length > 0) {
      const [activeGeneration, observed] = await Promise.all([
        service.desktop.activeGeneration().catch(() => undefined),
        service.desktop.observe().catch(unavailableObservation),
      ]);
      await Promise.all(
        interrupted.map((job) =>
          service.jobs.save({
            ...job,
            ...(activeGeneration === undefined ? {} : { activeGeneration }),
            observed,
            updatedAt: new Date().toISOString(),
            log: [...job.log, "Observed active generation and Waybar state after daemon restart"].slice(-64),
          }),
        ),
      );
    }
    return service;
  }

  async state(): Promise<ServiceState> {
    const [stored, jobs, activeGeneration, observed] = await Promise.all([
      this.profiles.read(),
      this.jobs.list(),
      this.desktop.activeGeneration().catch(() => undefined),
      this.desktop.observe().catch(unavailableObservation),
    ]);
    const source = await this.approvedSource().catch(() => undefined);
    const [evaluated, committedPreviewId] =
      source === undefined
        ? [undefined, undefined]
        : await Promise.all([
            this.resolved.load(source.source, stored.profile.revision, stored.hash),
            this.previews.findCommitted(source.source, stored.profile.revision, stored.hash),
          ]);
    if (evaluated !== undefined) this.catalog.validateOutput(evaluated.resolved);
    const state: ServiceState = {
      profile: stored.profile,
      components: this.catalog.presentation,
      resolved: evaluated?.resolved ?? {},
      resolvedIdentity: evaluated?.metadata ?? null,
      committedPreviewId: committedPreviewId ?? null,
      contracts: {
        inputSchema: this.catalog.inputDocument,
        outputSchema: this.catalog.outputDocument,
      },
      activeGeneration: activeGeneration ?? null,
      observed,
      jobs,
    };
    if (Buffer.byteLength(JSON.stringify(state), "utf8") > maxFrameBytes) {
      throw new DesktopSettingsError("unavailable", "Settings state exceeds the IPC frame limit");
    }
    return state;
  }

  async preview(request: PreviewRequest): Promise<SettingsPreview> {
    assertNonNegativeSafeInteger(request.expectedRevision, "Expected revision");
    const presentation = this.catalog.setting(request.component, request.setting);
    const current = await this.profiles.read();
    expectedRevision(current, request.expectedRevision);
    const components = structuredClone(current.profile.components);
    const existing = components[request.component];
    if (typeof existing !== "object" || existing === null || Array.isArray(existing)) {
      throw new DesktopSettingsError("unknown_setting", `Unknown component: ${request.component}`);
    }
    (existing as Record<string, unknown>)[request.setting] = request.value;
    this.catalog.validateComponents(components);
    const applyClass = presentation.setting.applyClass;
    if (typeof applyClass !== "string") {
      throw new DesktopSettingsError(
        "unavailable",
        `Generated presentation has no apply class for ${request.component}.${request.setting}`,
      );
    }
    const profile: Profile = {
      ...current.profile,
      revision: current.profile.revision + 1,
      components,
    };
    const source = await this.approvedSource();
    return this.profiles.withDraft(profile, async (snapshot) => {
      const evaluation = await this.evaluator.preview(
        snapshot.path,
        source.source,
        profile.revision,
        snapshot.hash,
      );
      const built = await this.builder.build(
        snapshot.path,
        source.source,
        profile.revision,
        snapshot.hash,
      );
      this.catalog.validateOutput(evaluation.resolved);
      this.catalog.validateOutput(built.resolved);
      const impact = {
        applyClass,
        requiresGeneration: applyClass !== "live",
      };
      const receipt = {
        id: crypto.randomUUID(),
        profileBytes: snapshot.bytes,
        profileHash: snapshot.hash,
        metadata: built.metadata,
        artifact: built.artifact,
        resolved: evaluation.resolved,
        impact,
        createdAt: new Date().toISOString(),
      };
      await Promise.all([this.resolved.save(evaluation), this.previews.save(receipt)]);
      return {
        id: receipt.id,
        profile,
        profileHash: snapshot.hash,
        identity: receipt.metadata,
        artifact: receipt.artifact,
        resolved: evaluation.resolved,
        impact,
      };
    });
  }

  async change(request: ChangeRequest): Promise<ServiceState> {
    await this.coordinator.run(async () => {
      assertNonNegativeSafeInteger(request.expectedRevision, "Expected revision");
      const current = await this.profiles.read();
      expectedRevision(current, request.expectedRevision);
      const receipt = await this.previews.read(request.previewId);
      if (receipt.committedAt !== undefined) {
        throw new DesktopSettingsError("invalid_request", "Preview identity has already committed a profile");
      }
      const source = await this.approvedSource();
      const components = structuredClone(current.profile.components);
      const existing = components[request.component];
      if (typeof existing !== "object" || existing === null || Array.isArray(existing)) {
        throw new DesktopSettingsError("unknown_setting", `Unknown component: ${request.component}`);
      }
      (existing as Record<string, unknown>)[request.setting] = request.value;
      this.catalog.validateComponents(components);
      const profile: Profile = {
        ...current.profile,
        revision: current.profile.revision + 1,
        components,
      };
      await this.profiles.withDraft(profile, async (snapshot) => {
        if (
          snapshot.bytes !== receipt.profileBytes ||
          snapshot.hash !== receipt.profileHash ||
          receipt.metadata.source !== source.source ||
          receipt.metadata.profileRevision !== profile.revision ||
          receipt.metadata.profileHash !== snapshot.hash
        ) {
          throw new DesktopSettingsError(
            "invalid_request",
            "Preview identity does not match the exact current profile candidate",
          );
        }
        await this.profiles.persist(profile);
        await this.previews.markCommitted(receipt);
      });
    });
    return this.state();
  }

  async createSavedCommand(request: CreateSavedCommandRequest): Promise<{ command: SavedCommand; state: ServiceState }> {
    const command = await this.coordinator.run(async () => {
      assertNonNegativeSafeInteger(request.expectedRevision, "Expected revision");
      const decoded = await Effect.runPromise(decodeCreateRequest(request.request)).catch((cause) => {
        throw new DesktopSettingsError(
          "invalid_request",
          cause instanceof Error ? cause.message : String(cause),
        );
      });
      const current = await this.profiles.read();
      expectedRevision(current, request.expectedRevision);
      let created = makeSavedCommand(decoded);
      while (lookupSavedCommand(current.profile.savedCommands, created.id) !== undefined) {
        created = makeSavedCommand(decoded);
      }
      await this.profiles.persist({
        ...current.profile,
        revision: current.profile.revision + 1,
        savedCommands: [...current.profile.savedCommands, created],
      });
      return created;
    });
    return { command, state: await this.state() };
  }

  async listSavedCommands(): Promise<Profile> {
    return (await this.profiles.read()).profile;
  }

  async lookupSavedCommand(request: SavedCommandLookupRequest): Promise<{ command: SavedCommand; profile: Profile }> {
    const profile = (await this.profiles.read()).profile;
    const command = lookupSavedCommand(profile.savedCommands, request.id);
    if (command === undefined) {
      throw new DesktopSettingsError("not_found", `Unknown saved-command ID: ${request.id}`);
    }
    return { command, profile };
  }

  async savedCommandProjection(): Promise<{
    profile: Profile;
    scripts: ReadonlyArray<SavedCommandProjection>;
  }> {
    const profile = (await this.profiles.read()).profile;
    return {
      profile,
      scripts: renderProjection(profile.savedCommands, this.config.riceCommand, this.config.shell),
    };
  }

  async apply(request: ApplyRequest): Promise<ApplyJob> {
    const scheduled = await this.coordinator.run(async () => {
      assertNonNegativeSafeInteger(request.expectedRevision, "Expected revision");
      const current = await this.profiles.read();
      expectedRevision(current, request.expectedRevision);
      const receipt = await this.previews.read(request.previewId);
      const source = await this.approvedSource();
      if (
        receipt.committedAt === undefined ||
        receipt.metadata.source !== source.source ||
        receipt.metadata.profileRevision !== current.profile.revision ||
        receipt.metadata.profileHash !== current.hash ||
        receipt.profileBytes !== current.bytes
      ) {
        throw new DesktopSettingsError(
          "invalid_request",
          "Preview identity is not the committed profile and approved source to apply",
        );
      }
      const profile = await this.profiles.snapshot(current);
      const jobs = await this.jobs.list();
      const running = jobs.find(
        (job) => job.status !== "active" && job.status !== "failed" && job.status !== "interrupted",
      );
      if (running !== undefined) {
        throw new DesktopSettingsError("apply_in_progress", "Another apply job is already in progress", {
          id: running.id,
          status: running.status,
        });
      }
      const reusable = jobs.find(
        (job) =>
          job.revision === profile.profile.revision &&
          job.profileHash === profile.hash &&
          job.source === receipt.metadata.source &&
          job.previewArtifact === receipt.artifact &&
          job.status === "active",
      );
      if (reusable !== undefined) return { job: reusable, profile };
      const now = new Date().toISOString();
      const job: ApplyJob = {
        id: crypto.randomUUID(),
        revision: profile.profile.revision,
        profileHash: profile.hash,
        source: receipt.metadata.source,
        previewArtifact: receipt.artifact,
        status: "queued",
        createdAt: now,
        updatedAt: now,
        log: ["Apply queued for the exact previewed artifact"],
      };
      await this.jobs.save(job);
      return { job, profile };
    });
    if (scheduled.job.status !== "active") {
      void this.startJob(scheduled.job, scheduled.profile).catch(() => undefined);
    }
    return scheduled.job;
  }

  private async runSerializedJob(job: ApplyJob, profile: StoredProfile): Promise<ApplyJob> {
    const previous = this.applyTail;
    let release: (() => void) | undefined;
    this.applyTail = new Promise<void>((resolve) => {
      release = resolve;
    });
    await previous.catch(() => undefined);
    try {
      return await this.runJob(job, profile);
    } finally {
      release?.();
    }
  }

  private async startJob(job: ApplyJob, profile: StoredProfile): Promise<ApplyJob> {
    const existing = this.running.get(job.id);
    if (existing !== undefined) return existing;
    const running = this.runSerializedJob(job, profile).finally(() => {
      this.running.delete(job.id);
    });
    this.running.set(job.id, running);
    return running;
  }
  async authorizationFailed(request: AuthorizationFailureRequest): Promise<ApplyJob> {
    return withAuthorityLock(this.config, () =>
      this.coordinator.run(async () => {
        const job = (await this.jobs.list()).find((candidate) => candidate.id === request.applyId);
        if (job === undefined || job.status !== "awaiting_authorization") {
          throw new DesktopSettingsError("not_found", "No apply job awaiting authorization");
        }
        const failed: ApplyJob = {
          ...job,
          ...appendLog(job, "Authorization was cancelled or denied"),
          status: "failed",
          updatedAt: new Date().toISOString(),
          error: {
            code: "activation_rejected",
            message: "Authorization was cancelled or denied",
          },
        };
        await this.jobs.save(failed);
        return failed;
      }),
    );
  }
  async reconcile(request: ReconcileRequest): Promise<ApplyJob> {
    return withAuthorityLock(this.config, () =>
      this.coordinator.run(async () => {
      const job = (await this.jobs.list()).find((candidate) => candidate.id === request.applyId);
      if (job === undefined || job.status !== "reconciling") {
        throw new DesktopSettingsError("not_found", "No activation awaiting runtime reconciliation");
      }
      const activeGeneration = await this.desktop.activeGeneration();
      const expected = {
        source: job.source,
        revision: job.revision,
        hash: job.profileHash,
      };
      if (
        activeGeneration === undefined ||
        activeGeneration.source !== expected.source ||
        activeGeneration.profileRevision !== expected.revision ||
        activeGeneration.profileHash !== expected.hash
      ) {
        const failed: ApplyJob = {
          ...job,
          ...appendLog(job, "Active generation did not match the root-authorized apply"),
          status: "failed",
          updatedAt: new Date().toISOString(),
          error: {
            code: "activation_rejected",
            message: "Active generation does not match the root-authorized apply",
          },
          ...(activeGeneration === undefined ? {} : { activeGeneration }),
          observed: request.observed,
        };
        await this.jobs.save(failed);
        return failed;
      }
      const observationWarning =
        request.observed.waybar.unit === "active" && request.observed.waybar.edge !== "unavailable"
          ? "Recorded untrusted user runtime observation after matching activation"
          : "Recorded untrusted user runtime warning after matching activation";
      const reconciled: ApplyJob = {
        ...job,
        ...appendLog(job, observationWarning),
        status: "active",
        updatedAt: new Date().toISOString(),
        activeGeneration,
        observed: request.observed,
      };
      await this.jobs.save(reconciled);
      return reconciled;
      }),
    );
  }
  private async runJob(initial: ApplyJob, profile: StoredProfile): Promise<ApplyJob> {
    let job = initial;

    const transition = async (status: ApplyJob["status"], message: string, patch: Partial<ApplyJob> = {}) => {
      job = { ...appendLog(job, message), ...patch, status };
      await this.jobs.save(job);
    };
    try {
      if (initial.source === undefined || initial.previewArtifact === undefined) {
        throw new DesktopSettingsError("activation_rejected", "Apply job has no immutable preview identity");
      }
      const source = initial.source;
      const previewArtifact = initial.previewArtifact;
      await transition("building", "Re-deriving the exact previewed workstation generation");
      const built = await this.builder.build(
        profile.revisionFile,
        source,
        profile.profile.revision,
        profile.hash,
      );
      if (built.artifact !== previewArtifact) {
        throw new DesktopSettingsError("activation_rejected", "Re-derived artifact differs from the approved preview", {
          previewArtifact,
          builtArtifact: built.artifact,
        });
      }
      this.catalog.validateOutput(built.resolved);
      await this.resolved.save({ metadata: built.metadata, resolved: built.resolved });
      await transition("awaiting_authorization", "Awaiting named polkit activation for the exact previewed artifact", {
        artifact: built.artifact,
      });
      return job;
    } catch (cause) {
      const observed = await this.desktop.observe().catch(unavailableObservation);
      job = {
        ...appendLog(job, `Apply failed: ${failure(cause).message}`),
        status: "failed",
        error: failure(cause),
        observed,
      };
      await this.jobs.save(job);
      return job;
    }
  }

  private async approvedSource(): Promise<ApprovedSource> {
    let text: string;
    try {
      text = await readFile(this.config.approvedSource, "utf8");
    } catch (cause) {
      throw new DesktopSettingsError(
        "unavailable",
        `Cannot read root-owned approved source marker: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    }
    const marker = await Effect.runPromise(
      parseJson(
        Schema.Struct({ source: Schema.String, host: Schema.String }),
        text,
        "approved source marker",
      ),
    ).catch((cause) => {
      if (cause instanceof DesktopSettingsError) throw cause;
      throw new DesktopSettingsError(
        "unavailable",
        `Invalid approved source marker: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    });
    return { source: marker.source, host: marker.host };
  }
}
