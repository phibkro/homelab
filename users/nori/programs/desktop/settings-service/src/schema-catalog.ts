/* runtime-adapter: read-only generated Home Manager contracts validated by Ajv 2020. */
import { readFile } from "node:fs/promises";
import Ajv2020 from "ajv/dist/2020.js";
import { Effect, Schema } from "effect";
import { DesktopSettingsError, parseJson } from "./contracts.ts";

type JsonObject = Record<string, unknown>;
type CompiledValidator = {
  (value: unknown): boolean;
  readonly errors?: ReadonlyArray<{ readonly instancePath?: string; readonly message?: string }> | null;
};

type SettingPresentation = {
  readonly component: JsonObject;
  readonly setting: JsonObject;
};

function expectObject(value: unknown, label: string): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new DesktopSettingsError("unavailable", `${label} must be a JSON object`);
  }
  return value as JsonObject;
}

function selectDefinition(document: JsonObject, label: string, name: string): JsonObject {
  const definitions = expectObject(document.$defs, `${label} $defs`);
  return expectObject(definitions[name], `${label} definition ${name}`);
}

function resolveLocalReference(document: JsonObject, schema: JsonObject): JsonObject {
  const reference = schema.$ref;
  if (typeof reference !== "string") return schema;
  const prefix = "#/$defs/";
  if (!reference.startsWith(prefix)) {
    throw new DesktopSettingsError("unavailable", `Unsupported generated schema reference: ${reference}`);
  }
  const definition = expectObject(document.$defs, "schema $defs")[reference.slice(prefix.length)];
  return resolveLocalReference(document, expectObject(definition, `schema definition ${reference}`));
}

function projectInputValue(document: JsonObject, schema: JsonObject, value: unknown): unknown {
  const resolved = resolveLocalReference(document, schema);
  const properties = resolved.properties;
  if (typeof value === "object" && value !== null && !Array.isArray(value) && properties !== undefined) {
    const projected: JsonObject = {};
    const propertyMap = expectObject(properties, "generated schema properties");
    for (const [key, property] of Object.entries(propertyMap)) {
      if (!(key in value)) continue;
      projected[key] = projectInputValue(
        document,
        expectObject(property, `generated schema property ${key}`),
        (value as JsonObject)[key],
      );
    }
    return projected;
  }
  if (Array.isArray(value) && resolved.items !== undefined) {
    return value.map((entry) =>
      projectInputValue(document, expectObject(resolved.items, "generated array items"), entry),
    );
  }
  return value;
}

async function loadJson(path: string, label: string): Promise<unknown> {
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch (cause) {
    throw new DesktopSettingsError(
      "unavailable",
      `Cannot read generated ${label}: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  return Effect.runPromise(parseJson(Schema.Unknown, text, `generated ${label}`));
}

export class SchemaCatalog {
  readonly inputDocument: JsonObject;
  readonly outputDocument: JsonObject;
  readonly inputRoot: JsonObject;
  readonly inputValidator: CompiledValidator;
  readonly presentation: JsonObject;
  readonly resolved: JsonObject;

  private constructor(
    inputDocument: JsonObject,
    outputDocument: JsonObject,
    inputRoot: JsonObject,
    inputValidator: CompiledValidator,
    presentation: JsonObject,
    resolved: JsonObject,
  ) {
    this.inputDocument = inputDocument;
    this.outputDocument = outputDocument;
    this.inputRoot = inputRoot;
    this.inputValidator = inputValidator;
    this.presentation = presentation;
    this.resolved = resolved;
  }

  static async load(dataDirectory: string): Promise<SchemaCatalog> {
    const rawInputDocument = expectObject(
      await loadJson(`${dataDirectory}/settings-input.schema.json`, "input schema"),
      "generated input schema",
    );
    const inputRoot = selectDefinition(
      rawInputDocument,
      "generated input schema",
      "NoriDesktopSettingsInput",
    );
    const rawOutputDocument = expectObject(
      await loadJson(`${dataDirectory}/settings-output.schema.json`, "output schema"),
      "generated output schema",
    );
    selectDefinition(
      rawOutputDocument,
      "generated output schema",
      "NoriDesktopSettingsOutput",
    );
    const inputDocument = rawInputDocument;
    const outputDocument = rawOutputDocument;
    const inputValidationDocument: JsonObject = {
      ...rawInputDocument,
      $ref: "#/$defs/NoriDesktopSettingsInput",
    };
    const presentation = expectObject(
      await loadJson(`${dataDirectory}/components.json`, "component catalog"),
      "generated component catalog",
    );
    const resolved = expectObject(
      await loadJson(`${dataDirectory}/resolved-settings.json`, "resolved settings"),
      "generated resolved settings",
    );
    const validator = new Ajv2020({ allErrors: true, strict: true }).compile(
      inputValidationDocument,
    ) as CompiledValidator;
    return new SchemaCatalog(
      inputDocument,
      outputDocument,
      inputRoot,
      validator,
      presentation,
      resolved,
    );
  }

  initialComponents(): Record<string, unknown> {
    return expectObject(
      projectInputValue(this.inputDocument, this.inputRoot, this.resolved),
      "profile components projected from generated resolved settings",
    );
  }

  validateComponents(components: Record<string, unknown>): void {
    if (this.inputValidator(components)) return;
    throw new DesktopSettingsError("invalid_profile", "Profile values do not satisfy generated settings schema", {
      errors: this.inputValidator.errors?.map((error) => ({
        path: error.instancePath ?? "",
        message: error.message ?? "invalid value",
      })),
    });
  }

  setting(componentId: string, settingId: string): SettingPresentation {
    const component = this.presentation[componentId];
    if (typeof component !== "object" || component === null || Array.isArray(component)) {
      throw new DesktopSettingsError("unknown_setting", `Unknown component: ${componentId}`);
    }
    const settings = (component as JsonObject).settings;
    if (typeof settings !== "object" || settings === null || Array.isArray(settings)) {
      throw new DesktopSettingsError("unknown_setting", `Component has no writable settings: ${componentId}`);
    }
    const setting = (settings as JsonObject)[settingId];
    if (typeof setting !== "object" || setting === null || Array.isArray(setting)) {
      throw new DesktopSettingsError("unknown_setting", `Unknown setting: ${componentId}.${settingId}`);
    }
    return { component: component as JsonObject, setting: setting as JsonObject };
  }
}
