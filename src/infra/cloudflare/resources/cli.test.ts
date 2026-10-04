import { describe, expect, test } from "bun:test";
import * as Config from "effect/Config";
import * as ConfigProvider from "effect/ConfigProvider";
import * as Effect from "effect/Effect";
import packageJson from "../package.json" with { type: "json" };

describe("operator Alchemy scripts", () => {
  for (const [name, command] of Object.entries(packageJson.scripts)) {
    if (!command.includes("alchemy ")) continue;
    test(name + " clears inherited CI before profile selection", () => {
      expect(command.startsWith("CI= ")).toBe(true);
    });
  }
  for (const [name, env, expected] of [["unset", {}, false], ["empty", { CI: "" }, false], ["true", { CI: "true" }, true]] as const) {
    test(name + " uses the installed Config.Boolean semantics", () => {
      const value = Effect.runSync(Config.Boolean("CI").pipe(Config.withDefault(false),
        Effect.provideService(ConfigProvider.ConfigProvider, ConfigProvider.fromEnvRecord(env))));
      expect(value).toBe(expected);
    });
  }
});
