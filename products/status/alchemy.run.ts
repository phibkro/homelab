import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import { retain } from "alchemy/RemovalPolicy";
import * as Effect from "effect/Effect";

export const StatusDatabase = Cloudflare.D1.Database("StatusDatabase", {
  primaryLocationHint: "weur",
  migrationsDir: "./migrations",
}).pipe(retain());

export const StatusWorker = Cloudflare.Worker(
  "StatusWorker",
  Effect.gen(function* () {
    const stage = yield* Alchemy.Stage;
    const production = stage === "prod";
    return {
      main: "./src/worker.ts",
      compatibility: { date: "2026-07-22" },
      domain: production ? "status.home.phibkro.org" : undefined,
      crons: production ? ["*/2 * * * *"] : [],
      env: { DB: StatusDatabase },
      url: !production,
      observability: {
        enabled: true,
        logs: { enabled: true, invocationLogs: true },
      },
    };
  }),
);

export type WorkerEnv = Cloudflare.InferEnv<typeof StatusWorker>;

export default Alchemy.Stack(
  "HomelabPublicStatus",
  {
    providers: Cloudflare.providers(),
    state: Cloudflare.state(),
  },
  Effect.gen(function* () {
    const database = yield* StatusDatabase;
    const worker = yield* StatusWorker;

    return {
      databaseName: database.databaseName,
      url: worker.url,
    };
  }),
);
