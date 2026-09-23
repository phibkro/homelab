/* runtime-adapter: durable, owner-only filesystem custody for profiles and jobs. */
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readdir,
  readFile,
  rename,
  rm,
  type FileHandle,
} from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { Effect } from "effect";
import {
  ApplyJob,
  DesktopSettingsError,
  EvaluationResult,
  ObservationRecord,
  PreviewReceipt,
  Profile,
  decodeJob,
  decodeObservationRecord,
  decodeProfile,
  parseJson,
  profileHash,
  type GenerationMetadata,
  type Observation,
} from "./contracts.ts";
import { maxFrameBytes } from "./framing.ts";

const fileMode = 0o600;
const directoryMode = 0o700;

/** Half of one state frame stays available for contracts, jobs, and runtime observations. */
export const maxProfileBytes = maxFrameBytes / 2;

export type StoredProfile = {
  readonly profile: Profile;
  readonly bytes: string;
  readonly hash: string;
  readonly revisionFile: string;
};

export type ProfileSnapshot = {
  readonly profile: Profile;
  readonly bytes: string;
  readonly hash: string;
  readonly path: string;
};

type ProfilePaths = {
  readonly profile: string;
  readonly revisions: string;
};

function describe(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}

function isMissing(cause: unknown): boolean {
  return cause instanceof Error && "code" in cause && cause.code === "ENOENT";
}

function assertProfileSize(bytes: string): void {
  if (new TextEncoder().encode(bytes).byteLength > maxProfileBytes) {
    throw new DesktopSettingsError(
      "invalid_profile",
      `Profile exceeds the ${maxProfileBytes}-byte settings-service limit`,
    );
  }
}

async function ensurePrivateDirectory(path: string): Promise<void> {
  await mkdir(path, { recursive: true, mode: directoryMode });
  const metadata = await lstat(path);
  if (
    !metadata.isDirectory() ||
    metadata.isSymbolicLink() ||
    metadata.uid !== process.getuid?.() ||
    (metadata.mode & 0o077) !== 0
  ) {
    throw new DesktopSettingsError(
      "unavailable",
      `Refusing unsafe settings-service directory: ${path}`,
    );
  }
}

async function ensurePrivateFile(path: string) {
  const metadata = await lstat(path);
  if (
    !metadata.isFile() ||
    metadata.isSymbolicLink() ||
    metadata.uid !== process.getuid?.() ||
    (metadata.mode & 0o077) !== 0
  ) {
    throw new DesktopSettingsError("invalid_profile", `Refusing unsafe file: ${path}`);
  }
  return metadata;
}

/** Durably replace one private file. A crash leaves the old or new complete file, never a partial write. */
export async function writeAtomic(path: string, content: string, mode = fileMode): Promise<void> {
  const parent = dirname(path);
  await ensurePrivateDirectory(parent);
  const temporary = join(parent, `.${basename(path)}.${process.pid}.${crypto.randomUUID()}.tmp`);
  let handle: FileHandle | undefined;
  try {
    handle = await open(temporary, "wx", mode);
    await handle.writeFile(content, "utf8");
    await handle.sync();
    await handle.close();
    handle = undefined;
    await chmod(temporary, mode);
    await rename(temporary, path);
    const directory = await open(parent, "r");
    try {
      await directory.sync();
    } finally {
      await directory.close();
    }
  } catch (cause) {
    throw new DesktopSettingsError("unavailable", `Cannot replace ${path}: ${describe(cause)}`);
  } finally {
    await handle?.close().catch(() => undefined);
    await rm(temporary, { force: true }).catch(() => undefined);
  }
}

async function readOptionalPrivateFile(path: string, maximumBytes?: number): Promise<string | undefined> {
  try {
    const metadata = await ensurePrivateFile(path);
    if (maximumBytes !== undefined && metadata.size > maximumBytes) {
      throw new DesktopSettingsError(
        "invalid_profile",
        `Profile exceeds the ${maximumBytes}-byte settings-service limit`,
      );
    }
    return await readFile(path, "utf8");
  } catch (cause) {
    if (isMissing(cause)) return undefined;
    throw cause;
  }
}

function encodeProfile(profile: Profile): string {
  return `${JSON.stringify(profile, null, 2)}\n`;
}

export class ProfileStore {
  readonly paths: ProfilePaths;

  constructor(configHome: string, stateHome: string) {
    this.paths = {
      profile: join(configHome, "profile.json"),
      revisions: join(stateHome, "revisions"),
    };
  }

  async initialize(initialComponents: Record<string, unknown>): Promise<StoredProfile> {
    await ensurePrivateDirectory(dirname(this.paths.profile));
    await ensurePrivateDirectory(this.paths.revisions);
    const existing = await readOptionalPrivateFile(this.paths.profile, maxProfileBytes);
    if (existing === undefined) {
      const profile: Profile = {
        formatVersion: 1,
        revision: 0,
        components: initialComponents,
        savedCommands: [],
      };
      return this.persist(profile);
    }
    return this.decodeStored(existing);
  }

  async read(): Promise<StoredProfile> {
    const bytes = await readOptionalPrivateFile(this.paths.profile, maxProfileBytes);
    if (bytes === undefined) {
      throw new DesktopSettingsError("unavailable", "Settings profile has not been initialized");
    }
    return this.decodeStored(bytes);
  }

  async persist(profile: Profile): Promise<StoredProfile> {
    const bytes = encodeProfile(profile);
    assertProfileSize(bytes);
    const hash = profileHash(bytes);
    const revisionFile = join(this.paths.revisions, `${profile.revision}-${hash}.json`);
    await writeAtomic(revisionFile, bytes);
    await writeAtomic(this.paths.profile, bytes);
    return { profile, bytes, hash, revisionFile };
  }

  async snapshot(stored: StoredProfile): Promise<StoredProfile> {
    await writeAtomic(stored.revisionFile, stored.bytes);
    return stored;
  }

  async withDraft<A>(
    profile: Profile,
    operation: (snapshot: ProfileSnapshot) => Promise<A>,
  ): Promise<A> {
    const directory = await mkdtemp(join(dirname(this.paths.revisions), ".preview-"));
    try {
      await chmod(directory, directoryMode);
      await ensurePrivateDirectory(directory);
      const path = join(directory, "profile.json");
      const bytes = encodeProfile(profile);
      assertProfileSize(bytes);
      await writeAtomic(path, bytes);
      return await operation({ profile, bytes, hash: profileHash(bytes), path });
    } finally {
      await rm(directory, { force: true, recursive: true }).catch(() => undefined);
    }
  }

  private async decodeStored(bytes: string): Promise<StoredProfile> {
    const profile = await Effect.runPromise(
      parseJson(Profile, bytes, "profile JSON").pipe(
        Effect.mapError(
          (error) => new DesktopSettingsError("invalid_profile", error.message),
        ),
        Effect.flatMap(decodeProfile),
      ),
    );
    const hash = profileHash(bytes);
    return {
      profile,
      bytes,
      hash,
      revisionFile: join(this.paths.revisions, `${profile.revision}-${hash}.json`),
    };
  }
}

/** Durable, non-authoritative Nix evaluation cache keyed by source and exact profile bytes. */
export class ResolvedStore {
  readonly directory: string;

  constructor(stateHome: string) {
    this.directory = join(stateHome, "resolved");
  }

  private path(metadata: GenerationMetadata): string {
    return join(this.directory, `${metadata.profileRevision}-${metadata.profileHash}.json`);
  }

  async initialize(): Promise<void> {
    await ensurePrivateDirectory(this.directory);
  }

  async save(evaluation: EvaluationResult): Promise<void> {
    await this.initialize();
    await writeAtomic(this.path(evaluation.metadata), `${JSON.stringify(evaluation, null, 2)}\n`);
  }

  async load(
    source: string,
    revision: number,
    hash: string,
  ): Promise<EvaluationResult | undefined> {
    await this.initialize();
    const bytes = await readOptionalPrivateFile(
      this.path({ source, profileRevision: revision, profileHash: hash }),
      maxProfileBytes,
    );
    if (bytes === undefined) return undefined;
    const evaluation = await Effect.runPromise(
      parseJson(EvaluationResult, bytes, `resolved evaluation ${revision}-${hash}`),
    );
    return evaluation.metadata.source === source &&
      evaluation.metadata.profileRevision === revision &&
      evaluation.metadata.profileHash === hash
      ? evaluation
      : undefined;
  }
}

/** Latest untrusted Waybar evidence submitted by the nori session runtime agent. */
export class ObservationStore {
  readonly path: string;

  constructor(stateHome: string) {
    this.path = join(stateHome, "observation.json");
  }

  async initialize(): Promise<void> {
    await ensurePrivateDirectory(dirname(this.path));
  }

  async save(observation: Observation): Promise<ObservationRecord> {
    await this.initialize();
    const record: ObservationRecord = {
      observedAt: new Date().toISOString(),
      observation,
    };
    await writeAtomic(this.path, `${JSON.stringify(record, null, 2)}\n`);
    return record;
  }

  async read(): Promise<ObservationRecord | undefined> {
    await this.initialize();
    const bytes = await readOptionalPrivateFile(this.path, maxProfileBytes);
    if (bytes === undefined) return undefined;
    return Effect.runPromise(
      parseJson(ObservationRecord, bytes, "runtime observation").pipe(
        Effect.flatMap(decodeObservationRecord),
      ),
    );
  }
}


function previewPath(directory: string, id: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    throw new DesktopSettingsError("invalid_request", "Invalid preview identity");
  }
  return join(directory, `${id}.json`);
}

/** Durable preview receipts bind a commit and apply to exact evaluated profile bytes. */
export class PreviewStore {
  readonly directory: string;

  constructor(stateHome: string) {
    this.directory = join(stateHome, "previews");
  }

  async initialize(): Promise<void> {
    await ensurePrivateDirectory(this.directory);
  }

  async save(receipt: PreviewReceipt): Promise<void> {
    await this.initialize();
    await writeAtomic(previewPath(this.directory, receipt.id), `${JSON.stringify(receipt, null, 2)}\n`);
  }

  async read(id: string): Promise<PreviewReceipt> {
    await this.initialize();
    const path = previewPath(this.directory, id);
    const bytes = await readOptionalPrivateFile(path, maxProfileBytes * 2);
    if (bytes === undefined) {
      throw new DesktopSettingsError("not_found", `Unknown preview identity: ${id}`);
    }
    const receipt = await Effect.runPromise(
      parseJson(PreviewReceipt, bytes, `preview receipt ${id}`),
    );
    await Effect.runPromise(
      parseJson(Profile, receipt.profileBytes, `preview profile ${id}`).pipe(Effect.flatMap(decodeProfile)),
    );
    if (profileHash(receipt.profileBytes) !== receipt.profileHash) {
      throw new DesktopSettingsError("invalid_profile", `Preview receipt ${id} has an invalid profile hash`);
    }
    return receipt;
  }

  async markCommitted(receipt: PreviewReceipt): Promise<void> {
    if (receipt.committedAt !== undefined) {
      throw new DesktopSettingsError("invalid_request", "Preview identity has already committed a profile");
    }
    await this.save({ ...receipt, committedAt: new Date().toISOString() });
  }

  async recoverCommitted(source: string, revision: number, hash: string): Promise<string | undefined> {
    await this.initialize();
    for (const name of await readdir(this.directory)) {
      if (!name.endsWith(".json")) continue;
      const receipt = await this.read(name.slice(0, -5));
      if (
        receipt.committedAt === undefined &&
        receipt.metadata.source === source &&
        receipt.metadata.profileRevision === revision &&
        receipt.metadata.profileHash === hash
      ) {
        await this.markCommitted(receipt);
        return receipt.id;
      }
    }
    return undefined;
  }

  async findCommitted(source: string, revision: number, hash: string): Promise<string | undefined> {
    await this.initialize();
    for (const name of await readdir(this.directory)) {
      if (!name.endsWith(".json")) continue;
      const receipt = await this.read(name.slice(0, -5));
      if (
        receipt.committedAt !== undefined &&
        receipt.metadata.source === source &&
        receipt.metadata.profileRevision === revision &&
        receipt.metadata.profileHash === hash
      ) {
        return receipt.id;
      }
    }
    return undefined;
  }
}

const maxTerminalJobs = 4;

function terminal(job: ApplyJob): boolean {
  return job.status === "active" || job.status === "failed" || job.status === "interrupted";
}
export class JobStore {
  readonly directory: string;

  constructor(stateHome: string) {
    this.directory = join(stateHome, "jobs");
  }

  async initialize(): Promise<void> {
    await ensurePrivateDirectory(this.directory);
  }

  async save(job: ApplyJob): Promise<void> {
    await writeAtomic(join(this.directory, `${job.id}.json`), `${JSON.stringify(job, null, 2)}\n`);
    const expired = (await this.list()).filter(terminal).slice(maxTerminalJobs);
    await Promise.all(
      expired.map((candidate) => rm(join(this.directory, `${candidate.id}.json`), { force: true })),
    );
  }

  async list(): Promise<ReadonlyArray<ApplyJob>> {
    await this.initialize();
    const names = await readdir(this.directory);
    const jobs: ApplyJob[] = [];
    for (const name of names) {
      if (!name.endsWith(".json")) continue;
      const bytes = await readOptionalPrivateFile(join(this.directory, name));
      if (bytes === undefined) continue;
      const job = await Effect.runPromise(
        parseJson(ApplyJob, bytes, `job ${name}`).pipe(Effect.flatMap(decodeJob)),
      );
      jobs.push(job);
    }
    return jobs.toSorted((left, right) => right.createdAt.localeCompare(left.createdAt));
  }

  async recoverInterrupted(): Promise<ReadonlyArray<ApplyJob>> {
    const jobs = await this.list();
    const recoveredIds = new Set<string>();
    for (const job of jobs) {
      if (terminal(job)) continue;
      const interrupted: ApplyJob = {
        ...job,
        status: "interrupted",
        updatedAt: new Date().toISOString(),
        error: {
          code: "interrupted",
          message: "The daemon restarted before this apply reached a terminal state",
        },
        log: [...job.log, "Daemon restart marked unfinished apply as interrupted"].slice(-64),
      };
      await this.save(interrupted);
      recoveredIds.add(interrupted.id);
    }
    return (await this.list()).filter((job) => recoveredIds.has(job.id));
  }
}
