import { describe, expect, test } from "bun:test";
import * as Effect from "effect/Effect";
import { decodeCompleteAccessList } from "./access.ts";

const path = "/access/apps/gateway/policies";
const servicePolicy = {
  id: "managed-policy",
  name: "Kwyne model gateway: service auth",
  decision: "non_identity",
  include: [{ service_token: { token_id: "f570199e-5bd4-4dd4-87b1-18a5c6168419" } }],
};

describe("Access list completeness", () => {
  test("accepts the entire first page using total_count, not total_pages", () => {
    const policies = Effect.runSync(decodeCompleteAccessList({
      result: [servicePolicy],
      result_info: { count: 1, page: 1, per_page: 20, total_count: 1 },
    }, path));
    expect(policies).toEqual([servicePolicy]);
  });

  test("accepts a verified empty list so a missing resource can be created", () => {
    const policies = Effect.runSync(decodeCompleteAccessList({
      result: [],
      result_info: { count: 0, page: 1, per_page: 20, total_count: 0 },
    }, path));
    expect(policies).toEqual([]);
  });

  const rejected = [
    { name: "partial first page", metadata: { count: 1, page: 1, per_page: 1, total_count: 2 } },
    { name: "later page", metadata: { count: 1, page: 2, total_count: 1 } },
    { name: "count mismatch", metadata: { count: 2, page: 1, total_count: 1 } },
    { name: "missing metadata", metadata: undefined },
    { name: "null metadata", metadata: null },
    { name: "missing total_count", metadata: { count: 1, page: 1 } },
    { name: "null total_count", metadata: { count: 1, page: 1, total_count: null } },
    { name: "missing page", metadata: { count: 1, total_count: 1 } },
    { name: "null page", metadata: { count: 1, page: null, total_count: 1 } },
    { name: "missing count", metadata: { page: 1, total_count: 1 } },
    { name: "obsolete total_pages only", metadata: { total_pages: 1 } },
    { name: "fractional total_count", metadata: { count: 1, page: 1, total_count: 1.5 } },
  ];
  for (const { name, metadata } of rejected) {
    test(`fails closed on ${name}`, () => {
      const error = Effect.runSync(Effect.flip(decodeCompleteAccessList({
        result: [servicePolicy], result_info: metadata,
      }, path)));
      expect(error._tag).toBe("AccessRequestError");
      expect(error.path).toBe(path);
    });
  }

  test("a hidden bypass policy cannot reach ownership selection or reconciliation", () => {
    // The returned policy looks safe; total_count reveals a second, hidden policy.
    let reachedSelection = false;
    const error = Effect.runSync(Effect.flip(decodeCompleteAccessList({
      result: [servicePolicy],
      result_info: { count: 1, page: 1, per_page: 1, total_count: 2 },
    }, path).pipe(Effect.map((policies) => {
      reachedSelection = true;
      return policies;
    }))));
    expect(error._tag).toBe("AccessRequestError");
    expect(error.message).toBe("Access list is incomplete; operator review required");
    expect(reachedSelection).toBe(false);
  });
});
