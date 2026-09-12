import { spawn } from "node:child_process";
import { Action, ActionPanel, Form, showToast, Toast } from "@vicinae/api";
import { useState } from "react";

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

