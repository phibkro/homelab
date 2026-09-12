import { spawn } from "node:child_process";
import { Action, ActionPanel, Form, showToast, Toast } from "@vicinae/api";
import { useCallback, useEffect, useState } from "react";

type JsonObject = Record<string, unknown>;

type SettingsState = {
  profile: {
    revision: number;
    components: JsonObject;
  };
  components: JsonObject;
  resolved: JsonObject;
  resolvedIdentity: unknown;
  committedPreviewId: string | null;
  activeGeneration: unknown;
  observed: JsonObject;
  jobs: unknown[];
};

type SettingsPreview = {
  id: string;
  selectedValue: string;
  expectedRevision: number;
  profileHash: string;
  resolved: unknown;
  impact: unknown;
};

type SettingPresentation = {
  title: string;
  description: string;
  applyClass: string | null;
};

class SettingsCliError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly details: unknown,
  ) {
    super(message);
  }
}

const terminalJobStatuses: Record<string, true> = {
  active: true,
  applied: true,
  "apply-failed": true,
  "build-failed": true,
  completed: true,
  failed: true,
  interrupted: true,
};

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function textFor(value: unknown): string {
  if (value === undefined) return "Unavailable";
  if (value === null) return "No value reported";
  if (typeof value === "string") return value;
  const text = JSON.stringify(value);
  return text.length > 280 ? `${text.slice(0, 277)}...` : text;
}

function settingValue(value: JsonObject, componentId: string, settingId: string): unknown {
  const component = value[componentId];
  return isJsonObject(component) ? component[settingId] : undefined;
}

function presentationFor(
  state: SettingsState,
  componentId: string,
  settingId: string,
): SettingPresentation | null {
  const component = state.components[componentId];
  if (!isJsonObject(component) || !isJsonObject(component.settings)) return null;
  const setting = component.settings[settingId];
  if (!isJsonObject(setting) || typeof setting.title !== "string" || typeof setting.description !== "string") {
    return null;
  }
  return {
    title: setting.title,
    description: setting.description,
    applyClass: typeof setting.applyClass === "string" ? setting.applyClass : null,
  };
}

function parseState(response: unknown): SettingsState {
  if (!isJsonObject(response) || response.ok !== true || !isJsonObject(response.state)) {
    throw new Error("nori-desktop-settings returned an invalid state response");
  }
  const state = response.state;
  const profile = state.profile;
  if (
    !isJsonObject(profile) ||
    typeof profile.revision !== "number" ||
    !isJsonObject(profile.components) ||
    !isJsonObject(state.components) ||
    !isJsonObject(state.resolved) ||
    !isJsonObject(state.observed) ||
    !(state.committedPreviewId === null || typeof state.committedPreviewId === "string") ||
    !Array.isArray(state.jobs)
  ) {
    throw new Error("nori-desktop-settings returned an incomplete state response");
  }
  return {
    profile: {
      revision: profile.revision,
      components: profile.components,
    },
    components: state.components,
    resolved: state.resolved,
    resolvedIdentity: state.resolvedIdentity,
    committedPreviewId: state.committedPreviewId,
    activeGeneration: state.activeGeneration,
    observed: state.observed,
    jobs: state.jobs,
  };
}

function parsePreview(
  response: unknown,
  componentId: string,
  settingId: string,
  selectedValue: string,
  expectedRevision: number,
): SettingsPreview {
  if (!isJsonObject(response) || response.ok !== true || !isJsonObject(response.preview)) {
    throw new Error("nori-desktop-settings returned an invalid preview response");
  }
  const preview = response.preview;
  if (
    !isJsonObject(preview.profile) ||
    !isJsonObject(preview.profile.components) ||
    typeof preview.id !== "string" ||
    typeof preview.profileHash !== "string" ||
    !("resolved" in preview) ||
    !("impact" in preview)
  ) {
    throw new Error("nori-desktop-settings returned an incomplete preview response");
  }
  if (settingValue(preview.profile.components, componentId, settingId) !== selectedValue) {
    throw new Error("nori-desktop-settings preview does not match the selected value");
  }
  return {
    id: preview.id,
    selectedValue,
    expectedRevision,
    profileHash: preview.profileHash,
    resolved: preview.resolved,
    impact: preview.impact,
  };
}

function parseResponse(stdout: string, stderr: string, status: number | null): unknown {
  let response: unknown;
  try {
    response = JSON.parse(stdout);
  } catch {
    throw new Error(stderr.trim() || `nori-desktop-settings exited ${status ?? "without a status"}`);
  }
  if (isJsonObject(response) && response.ok === false) {
    const error = response.error;
    if (isJsonObject(error) && typeof error.code === "string" && typeof error.message === "string") {
      throw new SettingsCliError(error.code, error.message, error.details);
    }
    throw new Error("nori-desktop-settings returned an invalid error response");
  }
  if (status !== 0 || !isJsonObject(response) || response.ok !== true) {
    throw new Error(stderr.trim() || `nori-desktop-settings exited ${status ?? "without a status"}`);
  }
  return response;
}

function invokeSettings(args: readonly string[]): Promise<unknown> {
  const { promise, resolve, reject } = Promise.withResolvers<unknown>();
  const child = spawn(
    process.env.RICE_NORI_DESKTOP_SETTINGS_BIN ?? "nori-desktop-settings",
    [...args, "--json"],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    stdout += chunk;
  });
  child.stderr.on("data", (chunk: string) => {
    stderr += chunk;
  });
  child.once("error", reject);
  child.once("close", (status) => {
    try {
      resolve(parseResponse(stdout, stderr, status));
    } catch (error) {
      reject(error);
    }
  });
  return promise;
}

function jobStatus(job: JsonObject): string {
  const status = job.status ?? job.phase ?? job.state;
  const error = job.error;
  if (error !== undefined) return `${textFor(status)}: ${textFor(error)}`;
  return textFor(status);
}

function jobsText(jobs: readonly unknown[]): string {
  if (jobs.length === 0) return "No managed system update has been requested.";
  return jobs
    .map((job) => {
      if (!isJsonObject(job)) return textFor(job);
      const id = typeof job.id === "string" ? job.id : "apply job";
      return `${id}: ${jobStatus(job)}`;
    })
    .join("\n");
}

function hasRunningJob(jobs: readonly unknown[]): boolean {
  return jobs.some((job) => {
    if (!isJsonObject(job)) return false;
    const status = job.status ?? job.phase ?? job.state;
    return typeof status === "string" && terminalJobStatuses[status] !== true;
  });
}

function observedText(state: SettingsState): string {
  const waybar = state.observed.waybar;
  if (!isJsonObject(waybar)) return textFor(state.observed);
  const unit = textFor(waybar.unit);
  const edge = textFor(waybar.edge);
  const reason = typeof waybar.reason === "string" ? `: ${waybar.reason}` : "";
  return `Waybar ${unit}, ${edge}${reason}`;
}

function errorText(error: unknown): string {
  if (error instanceof SettingsCliError && error.details !== undefined) {
    return `${error.message}\n${textFor(error.details)}`;
  }
  return error instanceof Error ? error.message : String(error);
}

type SettingFormProps = {
  componentId: string;
  settingId: string;
  values: readonly string[];
};

export function SettingForm({ componentId, settingId, values }: SettingFormProps) {
  const [state, setState] = useState<SettingsState | null>(null);
  const [selected, setSelected] = useState(values[0] ?? "");
  const [preview, setPreview] = useState<SettingsPreview | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(
    async (preserveFailure = false) => {
      setPreview(null);
      setLoading(true);
      try {
        const next = parseState(await invokeSettings(["state"]));
        setState(next);
        const desired = settingValue(next.profile.components, componentId, settingId);
        if (typeof desired === "string" && values.includes(desired)) setSelected(desired);
        if (!preserveFailure) setFailure(null);
      } catch (error) {
        setFailure(errorText(error));
        throw error;
      } finally {
        setLoading(false);
      }
    },
    [componentId, settingId, values],
  );

  useEffect(() => {
    void reload().catch(() => undefined);
  }, [reload]);

  const applying = state !== null && hasRunningJob(state.jobs);
  useEffect(() => {
    if (!applying) return;
    const timer = setInterval(() => {
      void reload().catch(() => undefined);
    }, 1000);
    return () => clearInterval(timer);
  }, [applying, reload]);

  const presentation = state === null ? null : presentationFor(state, componentId, settingId);
  const desired = state === null ? undefined : settingValue(state.profile.components, componentId, settingId);
  const resolved = state === null ? undefined : settingValue(state.resolved, componentId, settingId);

  async function reportFailure(title: string, error: unknown) {
    const message = errorText(error);
    setFailure(message);
    const toast = await showToast({ style: Toast.Style.Failure, title, message });
    if (error instanceof SettingsCliError && error.code === "revision_conflict") {
      try {
        await reload(true);
        toast.title = "Settings changed elsewhere";
        toast.message = "Reloaded the current revision before retrying.";
      } catch {
        toast.message = `${message} Reloading the newer revision also failed.`;
      }
    }
  }

  async function previewChange() {
    if (state === null || presentation === null) return;
    setPreview(null);
    const toast = await showToast({ style: Toast.Style.Animated, title: "Previewing change" });
    try {
      const nextPreview = parsePreview(
        await invokeSettings([
          "preview",
          componentId,
          settingId,
          JSON.stringify(selected),
          "--expected-revision",
          String(state.profile.revision),
        ]),
        componentId,
        settingId,
        selected,
        state.profile.revision,
      );
      setPreview(nextPreview);
      setFailure(null);
      toast.style = Toast.Style.Success;
      toast.title = "Change previewed";
      toast.message = "Review the generated impact, then save the desired value.";
    } catch (error) {
      await reportFailure("Could not preview change", error);
    }
  }

  async function save() {
    if (
      state === null ||
      presentation === null ||
      preview === null ||
      preview.selectedValue !== selected ||
      preview.expectedRevision !== state.profile.revision
    ) {
      return;
    }
    const toast = await showToast({ style: Toast.Style.Animated, title: "Saving desired value" });
    try {
      const next = parseState(
        await invokeSettings([
          "change",
          componentId,
          settingId,
          JSON.stringify(selected),
          "--expected-revision",
          String(state.profile.revision),
          "--preview",
          preview.id,
        ]),
      );
      setPreview(null);
      setFailure(null);
      toast.style = Toast.Style.Success;
      toast.title = "Desired value saved";
      toast.message = `Revision ${next.profile.revision} is ready for the managed system update.`;
    } catch (error) {
      await reportFailure("Could not save desired value", error);
    }
  }

  async function apply() {
    if (state === null || presentation === null) return;
    const toast = await showToast({ style: Toast.Style.Animated, title: "Starting system update" });
    try {
      if (state.committedPreviewId === null) {
        throw new Error("No durable preview matches the saved profile");
      }
      const response = await invokeSettings([
        "apply",
        "--expected-revision",
        String(state.profile.revision),
        "--preview",
        state.committedPreviewId,
      ]);
      if (!isJsonObject(response) || !("job" in response)) {
        throw new Error("nori-desktop-settings returned an invalid apply response");
      }
      toast.style = Toast.Style.Success;
      toast.title = "System update requested";
      toast.message = "Progress and the observed desktop state will refresh while the job runs.";
      try {
        await reload();
      } catch (error) {
        setFailure(errorText(error));
      }
    } catch (error) {
      await reportFailure("Could not start system update", error);
    }
  }

  const title = presentation?.title ?? "Desktop setting";
  const canPreview = state !== null && presentation !== null;
  const canSave =
    canPreview &&
    preview !== null &&
    preview.selectedValue === selected &&
    preview.expectedRevision === state.profile.revision;
  const hasUnsavedSelection = selected !== desired;
  return (
    <Form
      isLoading={loading}
      navigationTitle={title}
      actions={
        <ActionPanel>
          {canPreview ? <Action title="Preview Change" onAction={previewChange} /> : null}
          {canSave ? <Action.SubmitForm title="Save Desired Value" onSubmit={save} /> : null}
          {canPreview && !hasUnsavedSelection ? <Action title="Apply System Update" onAction={apply} /> : null}
          <Action
            title="Reload Settings"
            onAction={() => {
              void reload().catch(() => undefined);
            }}
          />
        </ActionPanel>
      }
    >
      <Form.Description
        title={title}
        text={presentation?.description ?? "The generated setting catalog is unavailable from the change service."}
      />
      <Form.Dropdown
        id="value"
        title={title}
        value={selected}
        onChange={(value) => {
          setSelected(value);
          setPreview(null);
        }}
      >
        {values.map((value) => (
          <Form.Dropdown.Item key={value} title={value} value={value} />
        ))}
      </Form.Dropdown>
      <Form.Description
        title="Preview"
        text={
          preview === null
            ? "Preview the selected value before saving it."
            : `Revision ${preview.expectedRevision}\nProfile hash: ${preview.profileHash}\nResolved: ${textFor(preview.resolved)}\nImpact: ${textFor(preview.impact)}`
        }
      />
      <Form.Separator />
      <Form.Description
        title="Desired"
        text={state === null ? "Loading the current profile revision." : `Revision ${state.profile.revision}: ${textFor(desired)}`}
      />
      <Form.Description title="Resolved" text={textFor(resolved)} />
      <Form.Description
        title="Resolved identity"
        text={textFor(state?.resolvedIdentity)}
      />
      <Form.Description
        title="Observed"
        text={state === null ? "Loading the active desktop observation." : observedText(state)}
      />
      <Form.Description title="Apply status" text={state === null ? "Loading durable jobs." : jobsText(state.jobs)} />
      {presentation?.applyClass === "generation" ? (
        <Form.Description
          title="System update required"
          text="Saving changes only records desired intent. Apply performs the managed system update, then the service reloads and observes the desktop surface."
        />
      ) : null}
      {failure !== null ? <Form.Description title="Last failure" text={failure} /> : null}
    </Form>
  );
}
