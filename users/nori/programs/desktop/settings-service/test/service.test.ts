import { afterEach, expect, test } from "bun:test";
import { mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DesktopSettingsError } from "../src/contracts.ts";
import { ProfileStore, writeAtomic } from "../src/files.ts";
import { verifyGenerationMetadata } from "../src/runtime.ts";
import { DesktopSettingsService, type ServiceConfig } from "../src/service.ts";

const temporaryDirectories: string[] = [];

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "nori-desktop-settings-"));
  temporaryDirectories.push(root);
  const dataDirectory = join(root, "data");
  await mkdir(dataDirectory, { recursive: true, mode: 0o700 });
  await Bun.write(
    join(dataDirectory, "settings-input.schema.json"),
    JSON.stringify({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      $defs: {
        NoriDesktopSettingsInput: {
          type: "object",
          properties: {
            "desktop.waybar": {
              type: "object",
              properties: { position: { enum: ["top", "bottom"] } },
              required: ["position"],
              additionalProperties: false,
            },
          },
          required: ["desktop.waybar"],
          additionalProperties: false,
        },
      },
    }),
  );
  await Bun.write(
    join(dataDirectory, "settings-output.schema.json"),
    JSON.stringify({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      $defs: { NoriDesktopSettingsOutput: { type: "object" } },
    }),
  );
  await Bun.write(
    join(dataDirectory, "components.json"),
    JSON.stringify({
      "desktop.waybar": {
        settings: { position: { title: "Bar position", control: "enum" } },
      },
    }),
  );
  await Bun.write(
    join(dataDirectory, "resolved-settings.json"),
    JSON.stringify({ "desktop.waybar": { position: "top", enabled: true } }),
  );
  const config: ServiceConfig = {
    configHome: join(root, "config"),
    stateHome: join(root, "state"),
    dataDirectory,
    approvedSource: join(root, "approved-source.json"),
    riceCommand: "rice-saved-command",
    shell: "/bin/sh",
    builder: "/does-not-run",
    evaluator: "/does-not-run",
    activator: "/does-not-run",
    activeMetadata: join(root, "generation.json"),
    systemctl: "/does-not-run",
    hyprctl: "/does-not-run",
    pkexec: "/does-not-run",
  };
  return { config, root };
}

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) => rm(directory, { force: true, recursive: true })),
  );
});

test("revision compare-and-swap preserves the first committed profile", async () => {
  const { config } = await fixture();
  const service = await DesktopSettingsService.make(config);
  const first = await service.change({
    component: "desktop.waybar",
    setting: "position",
    value: "bottom",
    expectedRevision: 0,
  });
  expect(first.profile.revision).toBe(1);
  expect(first.profile.components).toEqual({ "desktop.waybar": { position: "bottom" } });
  await expect(
    service.change({
      component: "desktop.waybar",
      setting: "position",
      value: "top",
      expectedRevision: 0,
    }),
  ).rejects.toMatchObject({ code: "revision_conflict" });
  expect((await service.state()).profile).toEqual(first.profile);
});

test("generated schema rejects a non-writable enum value before profile persistence", async () => {
  const { config } = await fixture();
  const service = await DesktopSettingsService.make(config);
  await expect(
    service.change({
      component: "desktop.waybar",
      setting: "position",
      value: "left",
      expectedRevision: 0,
    }),
  ).rejects.toMatchObject({ code: "invalid_profile" });
  expect((await service.state()).profile.revision).toBe(0);
  expect((await service.state()).profile.components).toEqual({
    "desktop.waybar": { position: "top" },
  });
});

test("an interrupted atomic replacement leaves the last complete profile readable", async () => {
  const { root } = await fixture();
  const store = new ProfileStore(join(root, "config", "nori-desktop"), join(root, "state", "nori-desktop"));
  const initial = await store.initialize({ "desktop.waybar": { position: "top" } });
  await Bun.write(`${store.paths.profile}.simulated-crash.tmp`, '{"revision":');
  expect((await store.read()).hash).toBe(initial.hash);
  expect(await readFile(store.paths.profile, "utf8")).toBe(initial.bytes);
  await writeAtomic(store.paths.profile, initial.bytes);
  expect((await store.read()).profile.revision).toBe(0);
});

test("activation metadata cannot substitute a different source, revision, or profile hash", () => {
  expect(() =>
    verifyGenerationMetadata(
      { source: "/nix/store/other-source", profileRevision: 2, profileHash: "other" },
      "/nix/store/approved-source",
      1,
      "expected",
    ),
  ).toThrow(DesktopSettingsError);
});
