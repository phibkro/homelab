import { expect, test } from "bun:test";
import { runStatusctl } from "../src/statusctl.ts";

function statusApi(calls: Array<{ url: string; body: unknown }>): typeof fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({
      url: input.toString(),
      body: JSON.parse(String(init?.body)) as unknown,
    });
    return new Response(JSON.stringify({ id: "maintenance-1" }), {
      status: 201,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
}

const environment = {
  STATUS_MUTATION_TOKEN: "operator-token",
  STATUS_API_URL: "https://status.example.test",
};
const now = () => new Date("2026-07-22T00:00:00Z");

test("maintained wrapper leaves the notice open when its command fails", async () => {
  const calls: Array<{ url: string; body: unknown }> = [];
  const result = await runStatusctl(
    ["maintained", "--title", "Deploy pi", "--", "false"],
    environment,
    statusApi(calls),
    now,
    async () => 23,
  );
  expect(result).toBe(23);
  expect(calls).toHaveLength(1);
  expect(calls[0]?.url).toEndWith("/api/operator/events");
});

test("maintained wrapper closes the notice only after success", async () => {
  const calls: Array<{ url: string; body: unknown }> = [];
  const commands: string[][] = [];
  let childToken: string | undefined;
  const result = await runStatusctl(
    ["maintained", "--title", "Deploy pi", "--", "just", "push", "pi"],
    environment,
    statusApi(calls),
    now,
    async (command, childEnvironment) => {
      commands.push(command);
      childToken = childEnvironment.STATUS_MUTATION_TOKEN;
      return 0;
    },
  );
  expect(result).toBe(0);
  expect(commands).toEqual([["just", "push", "pi"]]);
  expect(childToken).toBeUndefined();
  expect(calls).toHaveLength(2);
  expect(calls[1]?.url).toEndWith("/events/maintenance-1/updates");
  expect(calls[1]?.body).toEqual({
    state: "completed",
    message: "Maintenance completed successfully",
  });
});
