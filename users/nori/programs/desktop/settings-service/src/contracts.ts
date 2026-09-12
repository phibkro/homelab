/* schema-boundary: persisted profile, IPC requests, and public result records. */
import { createHash } from "node:crypto";
import { Effect, Schema } from "effect";
import {
  CreateCommandRequest,
  SavedCommand,
  decodeSavedCommands,
  strictParseOptions,
} from "./saved-command.ts";

export const Profile = Schema.Struct({
  formatVersion: Schema.Literal(1),
  revision: Schema.Number,
  components: Schema.Record(Schema.String, Schema.Unknown),
  savedCommands: Schema.Array(SavedCommand),
});

export type Profile = typeof Profile.Type;

export const PreviewRequest = Schema.Struct({
  component: Schema.String,
  setting: Schema.String,
  value: Schema.Unknown,
  expectedRevision: Schema.Number,
});

export type PreviewRequest = typeof PreviewRequest.Type;

export const ChangeRequest = Schema.Struct({
  component: Schema.String,
  setting: Schema.String,
  value: Schema.Unknown,
  expectedRevision: Schema.Number,
  previewId: Schema.String,
});
export type ChangeRequest = typeof ChangeRequest.Type;

export const ApplyRequest = Schema.Struct({
  expectedRevision: Schema.Number,
  previewId: Schema.String,
});
export type ApplyRequest = typeof ApplyRequest.Type;

export const AuthorizationFailureRequest = Schema.Struct({
  applyId: Schema.String,
});
export type AuthorizationFailureRequest = typeof AuthorizationFailureRequest.Type;


export const CreateSavedCommandRequest = Schema.Struct({
  request: CreateCommandRequest,
  expectedRevision: Schema.Number,
});

export type CreateSavedCommandRequest = typeof CreateSavedCommandRequest.Type;

export const SavedCommandLookupRequest = Schema.Struct({
  id: Schema.String,
});

export type SavedCommandLookupRequest = typeof SavedCommandLookupRequest.Type;

export const ActiveGeneration = Schema.Struct({
  path: Schema.String,
  source: Schema.String,
  profileRevision: Schema.Number,
  profileHash: Schema.String,
  bootDefault: Schema.optionalKey(Schema.Boolean),
});

export type ActiveGeneration = typeof ActiveGeneration.Type;

export const WaybarObservation = Schema.Struct({
  unit: Schema.Literals(["active", "inactive", "failed", "unknown"]),
  edge: Schema.Literals(["top", "bottom", "unavailable"]),
  reason: Schema.optionalKey(Schema.String),
});

export type WaybarObservation = typeof WaybarObservation.Type;


export const Observation = Schema.Struct({
  waybar: WaybarObservation,
});

export type Observation = typeof Observation.Type;

export const ReconcileRequest = Schema.Struct({
  applyId: Schema.String,
  observed: Observation,
});
export type ReconcileRequest = typeof ReconcileRequest.Type;

export const JobStatus = Schema.Literals([
  "queued",
  "building",
  "activating",
  "reconciling",
  "active",
  "awaiting_authorization",
  "failed",
  "interrupted",
]);

export type JobStatus = typeof JobStatus.Type;

export const JobFailure = Schema.Struct({
  code: Schema.String,
  message: Schema.String,
  details: Schema.optionalKey(Schema.Unknown),
});

export type JobFailure = typeof JobFailure.Type;

export const ApplyJob = Schema.Struct({
  id: Schema.String,
  revision: Schema.Number,
  profileHash: Schema.String,
  source: Schema.optionalKey(Schema.String),
  previewArtifact: Schema.optionalKey(Schema.String),
  status: JobStatus,
  createdAt: Schema.String,
  updatedAt: Schema.String,
  artifact: Schema.optionalKey(Schema.String),
  error: Schema.optionalKey(JobFailure),
  activeGeneration: Schema.optionalKey(ActiveGeneration),
  observed: Schema.optionalKey(Observation),
  log: Schema.Array(Schema.String),
});

export type ApplyJob = typeof ApplyJob.Type;

export const GenerationMetadata = Schema.Struct({
  source: Schema.String,
  profileRevision: Schema.Number,
  profileHash: Schema.String,
});

export const EvaluationResult = Schema.Struct({
  resolved: Schema.Record(Schema.String, Schema.Unknown),
  metadata: GenerationMetadata,
});

export type EvaluationResult = typeof EvaluationResult.Type;

export type GenerationMetadata = typeof GenerationMetadata.Type;

export const PreviewImpact = Schema.Struct({
  applyClass: Schema.String,
  requiresGeneration: Schema.Boolean,
});

export type PreviewImpact = typeof PreviewImpact.Type;

export const PreviewReceipt = Schema.Struct({
  id: Schema.String,
  profileBytes: Schema.String,
  profileHash: Schema.String,
  metadata: GenerationMetadata,
  artifact: Schema.String,
  resolved: Schema.Record(Schema.String, Schema.Unknown),
  impact: PreviewImpact,
  createdAt: Schema.String,
  committedAt: Schema.optionalKey(Schema.String),
});

export type PreviewReceipt = typeof PreviewReceipt.Type;

export const BuildResult = Schema.Struct({
  artifact: Schema.String,
  metadata: GenerationMetadata,
  resolved: Schema.Record(Schema.String, Schema.Unknown),
});

export type BuildResult = typeof BuildResult.Type;

export const ActivationResult = Schema.Struct({
  activeGeneration: ActiveGeneration,
});

export type ActivationResult = typeof ActivationResult.Type;

export type ErrorCode =
  | "activation_rejected"
  | "apply_in_progress"
  | "invalid_profile"
  | "invalid_request"
  | "job_failed"
  | "not_found"
  | "revision_conflict"
  | "runtime_unavailable"
  | "unknown_setting"
  | "unavailable";

export class DesktopSettingsError extends Error {
  readonly code: ErrorCode;
  readonly details: unknown;

  constructor(code: ErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = "DesktopSettingsError";
    this.code = code;
    this.details = details;
  }
}


export function profileHash(profileBytes: string): string {
  return createHash("sha256").update(profileBytes).digest("hex");
}

export function assertNonNegativeSafeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new DesktopSettingsError("invalid_request", `${label} must be a non-negative integer`);
  }
}

export function parseJson<A>(schema: Schema.ConstraintDecoder<A>, text: string, label: string) {
  return Schema.decodeUnknownEffect(Schema.fromJsonString(schema), strictParseOptions)(text).pipe(
    Effect.mapError(
      (error) => new DesktopSettingsError("invalid_request", `Invalid ${label}: ${error}`),
    ),
  );
}

export function decodeProfile(input: unknown) {
  return Schema.decodeUnknownEffect(Profile, strictParseOptions)(input).pipe(
    Effect.mapError(
      (error) => new DesktopSettingsError("invalid_profile", `Invalid profile: ${error}`),
    ),
    Effect.flatMap((profile) => {
      if (!Number.isSafeInteger(profile.revision) || profile.revision < 0) {
        return Effect.fail(
          new DesktopSettingsError("invalid_profile", "Profile revision must be a non-negative integer"),
        );
      }
      return decodeSavedCommands(profile.savedCommands).pipe(
        Effect.mapError(
          (error) => new DesktopSettingsError("invalid_profile", error.message),
        ),
        Effect.map((savedCommands) => ({ ...profile, savedCommands })),
      );
    }),
  );
}

export function decodeJob(input: unknown) {
  return Schema.decodeUnknownEffect(ApplyJob, strictParseOptions)(input).pipe(
    Effect.mapError((error) => new DesktopSettingsError("job_failed", `Invalid job record: ${error}`)),
  );
}

export function decodeGenerationMetadata(input: unknown) {
  return Schema.decodeUnknownEffect(GenerationMetadata, strictParseOptions)(input).pipe(
    Effect.mapError(
      (error) =>
        new DesktopSettingsError("activation_rejected", `Invalid generation metadata: ${error}`),
    ),
  );
}
