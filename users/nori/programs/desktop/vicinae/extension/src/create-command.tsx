import { spawn } from "node:child_process";
import { Action, ActionPanel, Form, showToast, Toast } from "@vicinae/api";
import { useCallback, useEffect, useState } from "react";

type OutputMode = "fullOutput" | "compact" | "silent" | "inline" | "terminal";

const outputModes: Record<OutputMode, true> = {
  compact: true,
  fullOutput: true,
  silent: true,
  inline: true,
  terminal: true,
};

type CreateResult = {
  command: { title: string };
  refreshed: boolean;
};

function textValue(values: Form.Values, key: string): string {
  const value = values[key];
  if (typeof value !== "string") throw new Error(`Missing form field: ${key}`);
  return value;
}

function booleanValue(values: Form.Values, key: string): boolean {
  const value = values[key];
  if (typeof value !== "boolean") throw new Error(`Missing form field: ${key}`);
  return value;
}

function outputModeValue(values: Form.Values): OutputMode {
  const value = textValue(values, "outputMode");
  if (value in outputModes) return value as OutputMode;
  throw new Error(`Unsupported output mode: ${value}`);
}

function parseCreateResult(text: string): CreateResult {
  const value: unknown = JSON.parse(text);
  if (
    typeof value !== "object" ||
    value === null ||
    !("command" in value) ||
    typeof value.command !== "object" ||
    value.command === null ||
    !("title" in value.command) ||
    typeof value.command.title !== "string" ||
    !("refreshed" in value) ||
    typeof value.refreshed !== "boolean"
  ) {
    throw new Error("rice-saved-command returned an invalid result");
  }
  return {
    command: { title: value.command.title },
    refreshed: value.refreshed,
  };
}

function createSavedCommand(request: object): Promise<CreateResult> {
  const { promise, resolve, reject } = Promise.withResolvers<CreateResult>();
  const child = spawn(process.env.RICE_SAVED_COMMAND_BIN ?? "rice-saved-command", ["create"], {
    stdio: ["pipe", "pipe", "pipe"],
  });
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
  child.on("error", reject);
  child.on("close", (status) => {
    if (status !== 0) {
      reject(new Error(stderr.trim() || `rice-saved-command exited ${status}`));
      return;
    }
    try {
      resolve(parseCreateResult(stdout));
    } catch {
      reject(new Error("rice-saved-command returned invalid JSON"));
    }
  });
  child.stdin.end(JSON.stringify(request));
  return promise;
}

export default function CreateCommand() {
  const [shellMode, setShellMode] = useState(false);

  async function submit(values: Form.Values) {
    const parameters = [
      {
        name: textValue(values, "parameter1").trim(),
        optional: booleanValue(values, "parameter1Optional"),
      },
      {
        name: textValue(values, "parameter2").trim(),
        optional: booleanValue(values, "parameter2Optional"),
      },
      {
        name: textValue(values, "parameter3").trim(),
        optional: booleanValue(values, "parameter3Optional"),
      },
    ].filter((parameter) => parameter.name.length > 0);
    const workingDirectory = textValue(values, "workingDirectory").trim();
    const request = {
      title: textValue(values, "title"),
      outputMode: outputModeValue(values),
      ...(workingDirectory.length === 0 ? {} : { workingDirectory }),
      parameters,
      execution: shellMode
        ? { type: "shell", source: textValue(values, "shellSource") }
        : {
            type: "argv",
            executable: textValue(values, "executable"),
            arguments: textValue(values, "arguments")
              .split("\n")
              .filter((argument) => argument.length > 0),
          },
    };

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Saving command",
    });
    try {
      const result = await createSavedCommand(request);
      toast.style = Toast.Style.Success;
      toast.title = `Saved ${result.command.title}`;
      toast.message = result.refreshed
        ? "Available in root search"
        : "Run Reload Script Directories if it does not appear yet";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not save command";
      toast.message = error instanceof Error ? error.message : String(error);
    }
  }

  return (
    <Form
      navigationTitle="Create Command"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Save Command" onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.TextField id="title" title="Title" placeholder="Deploy status page" />
      <Form.Checkbox
        id="shellMode"
        title="Execution"
        label="Explicit shell-script mode"
        value={shellMode}
        onChange={setShellMode}
      />
      {shellMode ? (
        <Form.TextArea id="shellSource" title="Shell source" placeholder={'printf "%s\\n" "$1"'} />
      ) : (
        <>
          <Form.TextField id="executable" title="Executable" placeholder="printf" />
          <Form.TextArea
            id="arguments"
            title="Arguments"
            placeholder={"One argument per line\n%s\\n\n{{message}}"}
          />
        </>
      )}
      <Form.TextField
        id="workingDirectory"
        title="Working directory"
        placeholder="Optional absolute path"
      />
      <Form.Separator />
      <Form.Description
        title="Parameters"
        text="Use {{name}} in argv arguments. Shell mode receives parameters as $1, $2, and $3."
      />
      <Form.TextField id="parameter1" title="Parameter 1" placeholder="message" />
      <Form.Checkbox id="parameter1Optional" title="Parameter 1" label="Optional" />
      <Form.TextField id="parameter2" title="Parameter 2" placeholder="Optional parameter name" />
      <Form.Checkbox id="parameter2Optional" title="Parameter 2" label="Optional" />
      <Form.TextField id="parameter3" title="Parameter 3" placeholder="Optional parameter name" />
      <Form.Checkbox id="parameter3Optional" title="Parameter 3" label="Optional" />
      <Form.Dropdown id="outputMode" title="Output" defaultValue="fullOutput">
        <Form.Dropdown.Item value="fullOutput" title="Full output" />
        <Form.Dropdown.Item value="compact" title="Notification" />
        <Form.Dropdown.Item value="silent" title="HUD" />
        <Form.Dropdown.Item value="inline" title="Inline subtitle" />
        <Form.Dropdown.Item value="terminal" title="Terminal" />
      </Form.Dropdown>
    </Form>
  );
}

type JsonObject = Record<string, unknown>;

type SettingsState = {
  profile: {
    revision: number;
    components: JsonObject;
  };
  components: JsonObject;
  resolved: JsonObject;
  activeGeneration: unknown;
  jobs: unknown[];
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
  ) {
    super(message);
  }
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function textFor(value: unknown): string {
  if (value === undefined) return "Unavailable";
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
    activeGeneration: state.activeGeneration,
    jobs: state.jobs,
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
      throw new SettingsCliError(error.code, error.message);
    }
    throw new Error("nori-desktop-settings returned an invalid error response");
  }
  if (status !== 0 || !isJsonObject(response) || response.ok !== true) {
    throw new Error(stderr.trim() || `nori-desktop-settings exited ${status ?? "without a status"}`);
  }
  return response;
}

function invokeSettings(args: readonly string[]): Promise<unknown> {
  return new Promise((resolve, reject) => {
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
  });
}

function jobsText(jobs: readonly unknown[]): string {
  if (jobs.length === 0) return "No managed system update has been requested.";
  return jobs
    .map((job) => {
      if (!isJsonObject(job)) return textFor(job);
      const id = typeof job.id === "string" ? job.id : "apply job";
      const status =
        typeof job.status === "string"
          ? job.status
          : typeof job.phase === "string"
            ? job.phase
            : textFor(job);
      return `${id}: ${status}`;
    })
    .join("\n");
}

function hasRunningJob(jobs: readonly unknown[]): boolean {
  return jobs.some((job) => {
    if (!isJsonObject(job)) return false;
    const status = job.status ?? job.phase;
    return !["active", "applied", "completed", "failed", "interrupted"].includes(
      typeof status === "string" ? status : "",
    );
  });
}

type SettingFormProps = {
  componentId: string;
  settingId: string;
  values: readonly string[];
};

export function SettingForm({ componentId, settingId, values }: SettingFormProps) {
  const [state, setState] = useState<SettingsState | null>(null);
  const [selected, setSelected] = useState(values[0] ?? "");
  const [failure, setFailure] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const next = parseState(await invokeSettings(["state"]));
      setState(next);
      const desired = settingValue(next.profile.components, componentId, settingId);
      if (typeof desired === "string" && values.includes(desired)) setSelected(desired);
      setFailure(null);
    } catch (error) {
      setFailure(error instanceof Error ? error.message : String(error));
      throw error;
    } finally {
      setLoading(false);
    }
  }, [componentId, settingId, values]);

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
    const message = error instanceof Error ? error.message : String(error);
    setFailure(message);
    const toast = await showToast({ style: Toast.Style.Failure, title, message });
    if (error instanceof SettingsCliError && error.code === "revision_conflict") {
      try {
        await reload();
        toast.title = "Settings changed elsewhere";
        toast.message = "Reloaded the current revision before retrying.";
      } catch {
        toast.message = `${message} Reloading the newer revision also failed.`;
      }
    }
  }

  async function save() {
    if (state === null || presentation === null) return;
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
        ]),
      );
      setState(next);
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
      const response = await invokeSettings([
        "apply",
        "--expected-revision",
        String(state.profile.revision),
      ]);
      if (!isJsonObject(response) || !("job" in response)) {
        throw new Error("nori-desktop-settings returned an invalid apply response");
      }
      await reload();
      toast.style = Toast.Style.Success;
      toast.title = "System update requested";
      toast.message = "Progress and the observed desktop state will refresh while the job runs.";
    } catch (error) {
      await reportFailure("Could not start system update", error);
    }
  }

  const title = presentation?.title ?? "Desktop setting";
  const canChange = state !== null && presentation !== null;
  return (
    <Form
      isLoading={loading}
      navigationTitle={title}
      actions={
        <ActionPanel>
          {canChange ? (
            <>
              <Action.SubmitForm title="Save Desired Value" onSubmit={save} />
              <Action title="Apply System Update" onAction={apply} />
            </>
          ) : null}
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
      <Form.Dropdown id="value" title={title} value={selected} onChange={setSelected}>
        {values.map((value) => (
          <Form.Dropdown.Item key={value} title={value} value={value} />
        ))}
      </Form.Dropdown>
      <Form.Separator />
      <Form.Description
        title="Desired"
        text={state === null ? "Loading the current profile revision." : `Revision ${state.profile.revision}: ${textFor(desired)}`}
      />
      <Form.Description title="Resolved" text={textFor(resolved)} />
      <Form.Description
        title="Observed"
        text={state === null ? "Loading the active desktop observation." : textFor(state.activeGeneration)}
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
