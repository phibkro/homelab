/* privileged-boundary: validate a complete persisted profile with the canonical Effect schema. */
import { Effect } from "effect";
import { DesktopSettingsError, decodeProfile, parseJson, Profile } from "./contracts.ts";

async function main(args: ReadonlyArray<string>): Promise<number> {
  if (args.length !== 2 || args[0] !== "--profile") {
    process.stderr.write("usage: nori-desktop-settings-validate-profile --profile PATH\n");
    return 64;
  }

  try {
    const bytes = await Bun.file(args[1]!).text();
    await Effect.runPromise(
      parseJson(Profile, bytes, "profile JSON").pipe(Effect.flatMap(decodeProfile)),
    );
    return 0;
  } catch (cause) {
    const message = cause instanceof DesktopSettingsError ? cause.message : String(cause);
    process.stderr.write(`nori-desktop-settings-validate-profile: ${message}\n`);
    return 65;
  }
}

process.exitCode = await main(Bun.argv.slice(2));
